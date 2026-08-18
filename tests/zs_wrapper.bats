#!/usr/bin/env bats
# @-name birth guard (FR-005): an @ session can never be born as a local
# shell — creation derives the ssh command from the name. Vectors from
# contracts/name-mapping.md. Exercised via `zs --pick-token` is internal, so
# we drive run_choice through the picker's s:-token path using --attach and
# the stale-row simulation (empty fake list = session doesn't exist).
load helpers

setup() { setup_shims; }

# Vector table: creating each @ name must run the mapped ssh command.
# zs's s:-token path is reached via attach_wrapper; we exercise it through
# a stale-row pick simulation: zs --attach uses attach_run directly, so the
# vectors are asserted through the picker path (ZS_TEST_TOKEN) instead.
vector() { # $1 name, $2 expected ssh target
    : > "$ZMX_FAKE_LOG"
    run zs --pick-test "s:$1"
    assert_log_has "zmx attach $1 ssh $2" "$ZMX_FAKE_LOG"
}

@test "vectors: numbered wrappers connect to the bare host" {
    vector "@myhost.1" "myhost"
    vector "@myhost.12" "myhost"
    vector "@my-ws-01.3" "my-ws-01"
}

@test "vectors: bare wrapper connects to the host" {
    vector "@myhost" "myhost"
}

@test "vectors: pinned and sibling wrappers keep the full spec" {
    vector "@myhost.dev" "myhost.dev"
    vector "@myhost.dev.2" "myhost.dev.2"
    vector "@myhost.dev.boot" "myhost.dev.boot"
    vector "@myhost.dev.boot.2" "myhost.dev.boot.2"
}

@test "plain (non-@) names attach with no command (unchanged v2)" {
    run zs --pick-test "s:proj.1"
    assert_log_has "zmx attach proj.1" "$ZMX_FAKE_LOG"
    assert_log_lacks "ssh" "$ZMX_FAKE_LOG"
}

@test "headless zs --attach passes the command through and reap-checks (FR-013)" {
    run zs --attach worker.1 sleep 5
    assert_log_has "zmx attach worker.1 sleep 5" "$ZMX_FAKE_LOG"
    assert_log_has "zmx list" "$ZMX_FAKE_LOG"   # corpse-reap check after attach
}

@test "headless zs --attach reaps an ended corpse and exits 0" {
    fixture_row worker.1 11 0 100 /tmp "ended=200" "exit_code=0"
    run zs --attach worker.1
    [ "$status" -eq 0 ]
    assert_log_has "zmx kill worker.1" "$ZMX_FAKE_LOG"
}
