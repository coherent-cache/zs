#!/usr/bin/env bats
# 7-day corpse auto-reap at picker start (FR-012) — and the FR-014 guardrail:
# detached (clients=0) is NOT dead; only ended= corpses may ever be reaped.
load helpers

setup() { setup_shims; NOW=$(date +%s); }

@test "corpses ended >7 days ago are reaped at --list" {
    fixture_row ancient 11 0 100 /tmp "ended=$((NOW - 8*86400))" "exit_code=0"
    run zs --list --only=local
    assert_log_has "zmx kill ancient" "$ZMX_FAKE_LOG"
    [[ "$output" != *"s:ancient"* ]]
}

@test "younger corpses stay visible as rows" {
    fixture_row recent 11 0 100 /tmp "ended=$((NOW - 2*86400))" "exit_code=1"
    run zs --list --only=local
    assert_log_lacks "zmx kill" "$ZMX_FAKE_LOG"
    [[ "$output" == *"s:recent"* ]]
}

@test "FR-014: detached agent sessions are never touched, however old" {
    fixture_row agent.1 11 0 100 /tmp "cmd=agent --resume abc"
    fixture_row idle.2  12 0 200 /tmp
    run zs --list --only=local
    assert_log_lacks "zmx kill" "$ZMX_FAKE_LOG"
    [[ "$output" == *"s:agent.1"* ]]
    [[ "$output" == *"s:idle.2"* ]]
}
