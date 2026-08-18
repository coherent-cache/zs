#!/usr/bin/env bats
# Quick-connect classification (q: tokens) and host-row resume-candidate
# selection (h: tokens) — FR-010/SC-003, via the internal --pick-test seam.
load helpers

setup() {
    setup_shims
    printf 'Host myhost\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
}

log_has_exact() { grep -qxF -- "$1" "$ZMX_FAKE_LOG" || { echo "expected exact '$1' in zmx log:"; cat "$ZMX_FAKE_LOG"; return 1; }; }

# ── q: classification ────────────────────────────────────────────────────────

@test "q: user@host creates a wrapper running ssh user@host" {
    run zs --pick-test "q:alice@myhost"
    log_has_exact "zmx attach @myhost.1 ssh alice@myhost"
}

@test "q: host.sess with a KNOWN host pins a deterministic wrapper" {
    run zs --pick-test "q:myhost.dev"
    log_has_exact "zmx attach @myhost.dev ssh myhost.dev"
}

@test "q: dotted name with an UNKNOWN first segment stays local" {
    run zs --pick-test "q:notahost.x"
    log_has_exact "zmx attach notahost.x"
    assert_log_lacks "ssh" "$ZMX_FAKE_LOG"
}

@test "q: plain word creates a local session" {
    run zs --pick-test "q:scratch"
    log_has_exact "zmx attach scratch"
    assert_log_lacks "ssh" "$ZMX_FAKE_LOG"
}

# ── explicit-wrapper (q:@host) resume-candidate selection ───────────────────
# spec 003 US3 [Δ002]: this logic moved from the h: host row (now a plain
# connect) to the EXPLICIT @host spelling — same resume-or-create semantics.

@test "q:@host resumes a detached non-ended wrapper instead of creating" {
    fixture_row @myhost.1 11 0 100 /tmp "cmd=ssh myhost"
    run zs --pick-test "q:@myhost"
    log_has_exact "zmx attach @myhost.1"
}

@test "q:@host newest detached wrapper wins" {
    fixture_row @myhost.1 11 0 100 /tmp "cmd=ssh myhost"
    fixture_row @myhost.2 12 0 300 /tmp "cmd=ssh myhost"
    run zs --pick-test "q:@myhost"
    log_has_exact "zmx attach @myhost.2"
}

@test "q:@host an ended corpse is not a resume candidate (creates, name poisoned)" {
    fixture_row @myhost.1 11 0 100 /tmp "cmd=ssh myhost" "ended=$(($(date +%s) - 3600))" "exit_code=255"
    run zs --pick-test "q:@myhost"
    log_has_exact "zmx attach @myhost.2 ssh myhost"
}

@test "q:@host an ATTACHED wrapper is not a resume candidate (creates a new one)" {
    fixture_row @myhost.1 11 1 100 /tmp "cmd=ssh myhost"
    run zs --pick-test "q:@myhost"
    log_has_exact "zmx attach @myhost.2 ssh myhost"
}

@test "003: the plain host row is a one-layer ssh, never a wrapper" {
    run zs --pick-test "h:myhost"
    grep -qxF "ssh myhost" "$SSH_FAKE_LOG"
    ! grep -q "zmx attach" "$ZMX_FAKE_LOG"
    ! grep -q "zn " "$SSH_FAKE_LOG"
}

# ── @-name dotted-host disambiguation (2026-07-22 fix) ──────────────────────

@test "@IP is NOT shredded into host.session — plain-connects to the whole IP" {
    printf 'Host ws15\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --pick-test "q:@100.64.0.7"
    grep -qF "ssh 100.64.0.7" "$SSH_FAKE_LOG"     # whole IP as one host (h: plain connect)
    ! grep -q "attach @100" "$ZMX_FAKE_LOG"          # never a shredded @1.2.3.4 wrapper
    ! grep -q "ssh 100$" "$SSH_FAKE_LOG"             # and never ssh'd "100" alone
}

@test "@FQDN (unknown first segment) plain-connects to the whole name" {
    printf 'Host ws15\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --pick-test "q:@box.example.com"
    grep -qF "ssh box.example.com" "$SSH_FAKE_LOG"
    ! grep -q "attach @box" "$ZMX_FAKE_LOG"
}

@test "@knownhost.session still makes the dispatcher wrapper (unchanged)" {
    printf 'Host ws15\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --pick-test "q:@ws15.mesh"
    log_has_exact "zmx attach @ws15.mesh ssh ws15.mesh"
}

@test "a wrapper connect that dies immediately is NOT silent" {
    fixture_row @ws15.1 11 0 100 /tmp "cmd=ssh ws15" "ended=$(date +%s)" "exit_code=255"
    run zs --pick-test "s:@ws15.1"
    [[ "$output" == *"closed immediately"* ]]
    [[ "$output" == *"ssh ws15"* ]]                  # names the command to re-run
}
