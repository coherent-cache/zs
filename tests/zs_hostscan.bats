#!/usr/bin/env bats
# Regression pins for 0f6211f (host-scan cost): a cold picker took 36s and a
# warm one 3.6s because every name was resolved sequentially AND self-host
# checks re-resolved per row per render. These tests pin the CALL COUNTS the
# fix guarantees; "first-listed alias wins" ordering is already pinned in
# zs_list.bats ("hosts dedupe by resolved endpoint keeps first-listed alias",
# which fails if reassembly ever sorts by name — long-alias < short).
load helpers

setup() { setup_shims; }

three_hosts() {
    printf 'Host b1\n  HostName 1.1.1.1\nHost b2\n  HostName 2.2.2.2\nHost b3\n  HostName 3.3.3.3\n' \
        > "$HOME/.ssh/config"
}

@test "0f6211f: a COLD render resolves each name exactly once (parallel fan-out, no re-resolution)" {
    three_hosts
    run zs --list --only=remote
    [[ "$output" == *"h:b1"* ]]
    [[ "$output" == *"h:b2"* ]]
    [[ "$output" == *"h:b3"* ]]
    # one ssh -G per configured name — a lost parallel slot shows as <3,
    # a self-host or dedup re-resolution shows as >3
    [ "$(grep -c '^ssh -G' "$SSH_FAKE_LOG")" -eq 3 ]
}

@test "0f6211f: a WARM render resolves NOTHING (endpoint cache serves dedup and self-host)" {
    three_hosts
    run zs --list --only=remote            # cold: builds ~/.cache/zs/hosts
    : > "$SSH_FAKE_LOG"
    run zs --list --only=remote            # warm
    [[ "$output" == *"h:b1"* ]]
    [ "$(grep -c '^ssh -G' "$SSH_FAKE_LOG")" -eq 0 ]
}

@test "0f6211f: editing the ssh config invalidates the cache (cold again, once)" {
    three_hosts
    run zs --list --only=remote
    : > "$SSH_FAKE_LOG"
    sleep 1     # mtime granularity: config must be strictly newer than cache
    printf 'Host b4\n  HostName 4.4.4.4\n' >> "$HOME/.ssh/config"
    run zs --list --only=remote
    [[ "$output" == *"h:b4"* ]]
    [ "$(grep -c '^ssh -G' "$SSH_FAKE_LOG")" -eq 4 ]
}
