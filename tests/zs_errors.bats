#!/usr/bin/env bats
# spec 004 US1 — no silent failures.
#
# The bug this guards: `_remote_zmx` discarded stderr (`2>/dev/null`), so a
# host that refuses this machine's key reported "no zmx / unreachable" — the
# same text as a dead host. Worse, a live connection-sharing master made the
# SAME host succeed intermittently, so it read as random flakiness rather than
# a deterministic auth refusal.
#
# OpenSSH returns 255 for every client-side failure, so these tests drive the
# ssh shim's $SSH_FAKE_STDERR (not just $SSH_FAKE_RC) — a classifier that reads
# only the exit status cannot pass them.
load helpers

setup() { setup_shims; }

# ── classifier unit cases ────────────────────────────────────────────────────

@test "classify: Permission denied => auth-denied" {
    run zs --classify 255 "user@host: Permission denied (publickey,password)."
    [ "$status" -eq 0 ]
    [[ "$output" == auth-denied* ]]
}

@test "classify: missing identity file => auth-denied (not no-zmx)" {
    # the real mac14 case: Host * points at an id_rsa that does not exist here
    run zs --classify 255 "no such identity: /home/u/.ssh/id_rsa: No such file or directory
user@host: Permission denied (publickey)."
    [ "$status" -eq 0 ]
    [[ "$output" == auth-denied* ]]
}

@test "classify: timed out / refused / unresolvable => unreachable" {
    for e in "ssh: connect to host h port 22: Connection timed out" \
             "ssh: connect to host h port 22: Connection refused" \
             "ssh: Could not resolve hostname h: Name or service not known"; do
        run zs --classify 255 "$e"
        [[ "$output" == unreachable* ]] || { echo "not unreachable: $e => $output"; return 1; }
    done
}

@test "classify: command not found / rc=127 => no-zmx" {
    run zs --classify 127 "bash: line 1: zmx: command not found"
    [[ "$output" == no-zmx* ]]
    run zs --classify 127 ""
    [[ "$output" == no-zmx* ]]
}

@test "classify: rc=0 with no output => empty (reachable, no sessions)" {
    run zs --classify 0 ""
    [[ "$output" == empty* ]]
}

@test "classify: unrecognised failure keeps its first stderr line, not a generic message" {
    run zs --classify 255 "kex_exchange_identification: read: Connection reset by peer"
    [[ "$output" == unknown* ]]
    [[ "$output" == *"kex_exchange_identification"* ]]
}

# ── drill rows carry the class (US1 acceptance 1-3) ──────────────────────────

@test "drill: auth refusal says AUTH, not 'no zmx / unreachable'" {
    SSH_FAKE_RC=255 SSH_FAKE_STDERR="user@h: Permission denied (publickey,password)." \
        run zs --drill-rows h:somehost
    [ "$status" -eq 0 ]
    [[ "$output" == *"auth"* ]]
    [[ "$output" != *"no zmx / unreachable"* ]]
}

@test "drill: unreachable host is distinct from auth refusal" {
    SSH_FAKE_RC=255 SSH_FAKE_STDERR="ssh: connect to host h port 22: Connection timed out" \
        run zs --drill-rows h:somehost
    [[ "$output" == *"unreachable"* || "$output" == *"connection"* ]]
    [[ "$output" != *"auth"* ]]
}

@test "drill: connected but no zmx says so" {
    SSH_FAKE_RC=127 SSH_FAKE_STDERR="bash: zmx: command not found" \
        run zs --drill-rows h:somehost
    [[ "$output" == *"no zmx"* ]]
}

# ── public-repo hygiene (Constitution IV / contract §3) ──────────────────────

@test "messages name the alias only — no resolved address, user, or raw stderr leak" {
    SSH_FAKE_RC=255 \
    SSH_FAKE_STDERR="ssh: connect to host 10.11.12.13 port 22: Connection timed out
debug1: identity file /home/somebody/.ssh/id_rsa" \
        run zs --drill-rows h:somehost
    [[ "$output" == *"somehost"* ]]        # the alias IS named
    [[ "$output" != *"10.11.12.13"* ]]     # ...but never the address
    [[ "$output" != *"/home/somebody"* ]]  # ...nor a path/username from stderr
}

# ── US2: never offer / connect to this machine ───────────────────────────────

@test "self host: a row whose alias is this machine is suppressed" {
    hn=$(hostname -s 2>/dev/null || hostname)
    printf 'Host %s\n  HostName 1.2.3.4\nHost other\n  HostName 5.6.7.8\n' "$hn" > "$HOME/.ssh/config"
    run zs --list --only=remote
    [[ "$output" != *"h:$hn"* ]]   # self suppressed
    [[ "$output" == *"h:other"* ]] # others untouched
}

@test "self host: explicitly choosing this machine explains instead of connecting" {
    hn=$(hostname -s 2>/dev/null || hostname)
    printf 'Host %s\n  HostName 1.2.3.4\n' "$hn" > "$HOME/.ssh/config"
    run zs --pick-test "h:$hn"
    [[ "$output" == *"this machine"* ]]
    ! grep -qxF "ssh $hn" "$SSH_FAKE_LOG"   # no circular connect attempted
}
