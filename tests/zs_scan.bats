#!/usr/bin/env bats
# spec 005 — scan-path lite. Contract C1/C2: a render derives EVERYTHING
# (rows, dup warnings, host recency, verprobe candidacy) from ONE zmx list.
# Contract C3/C4: expired corpses are suppressed in the same render and
# killed via one batched, non-blocking zmx kill (ZS_REAP_WAIT=1 makes the
# dispatch synchronous for deterministic assertions — no sleeps, FR-009).
load helpers

setup() { setup_shims; }

scan_fixtures() {
    fixture_row plain.1 11 0 100 /tmp
    fixture_row tagged.1 12 1 200 /tmp "role=x"
    fixture_row @far.1 13 1 300 /tmp "cmd=ssh far.1"
}

# ── C1: exactly one listing per render, in every view ────────────────────────

@test "005 C1: --only=all renders from ONE zmx list" {
    scan_fixtures
    run zs --list
    [[ "$output" == *"s:plain.1"* ]]
    [ "$(grep -c '^zmx list' "$ZMX_FAKE_LOG")" -eq 1 ]
}

@test "005 C1: --only=local renders from ONE zmx list" {
    scan_fixtures
    run zs --list --only=local
    [[ "$output" == *"s:tagged.1"* ]]
    [ "$(grep -c '^zmx list' "$ZMX_FAKE_LOG")" -eq 1 ]
}

@test "005 C1: --only=remote renders from ONE zmx list" {
    scan_fixtures
    run zs --list --only=remote
    [[ "$output" == *"s:@far.1"* ]]
    [ "$(grep -c '^zmx list' "$ZMX_FAKE_LOG")" -eq 1 ]
}

@test "005 C1: --only=label:k=v renders from ONE zmx list" {
    scan_fixtures
    run zs --list --only=label:role=x
    [[ "$output" == *"s:tagged.1"* ]]
    [[ "$output" != *"s:plain.1"* ]]
    [ "$(grep -c '^zmx list' "$ZMX_FAKE_LOG")" -eq 1 ]
}

# ── C2: derived views stay correct from the single capture ───────────────────

@test "005 C2: duplicate-name warning still renders, single listing" {
    fixture_row twin 21 0 100 /tmp
    fixture_row twin 22 0 200 /tmp
    run zs --list --only=local
    [[ "$output" == *"duplicate name"* ]]
    [ "$(grep -c '^zmx list' "$ZMX_FAKE_LOG")" -eq 1 ]
}

@test "005 C2: wrapper host-recency ordering intact, single listing" {
    # attached wrapper's host must outrank the older detached wrapper's host
    fixture_row @old.9 31 0 100 /tmp "cmd=ssh old.9"
    fixture_row_arrow @fresh.1 32 1 900 /tmp "cmd=ssh fresh.1"
    run zs --list --only=remote
    f=$(grep -n "s:@fresh.1" <<<"$output" | cut -d: -f1)
    o=$(grep -n "s:@old.9"  <<<"$output" | cut -d: -f1)
    [ -n "$f" ] && [ -n "$o" ] && [ "$f" -lt "$o" ]
    [ "$(grep -c '^zmx list' "$ZMX_FAKE_LOG")" -eq 1 ]
}

# ── C3/C4: batched, non-blocking reap ────────────────────────────────────────

@test "005 C3: expired corpses suppressed; ONE batched kill names all three" {
    fixture_row dead.1 41 0 100 /tmp "ended=1000" "exit_code=0"
    fixture_row dead.2 42 0 100 /tmp "ended=1001" "exit_code=1"
    fixture_row dead.3 43 0 100 /tmp "ended=1002" "exit_code=0"
    fixture_row live.1 44 1 200 /tmp
    ZS_REAP_WAIT=1 run zs --list --only=local
    [[ "$output" == *"s:live.1"* ]]
    [[ "$output" != *"dead.1"* ]]
    [[ "$output" != *"dead.2"* ]]
    [[ "$output" != *"dead.3"* ]]
    [ "$(grep -c '^zmx kill' "$ZMX_FAKE_LOG")" -eq 1 ]
    line=$(grep '^zmx kill' "$ZMX_FAKE_LOG")
    [[ "$line" == *"dead.1"* && "$line" == *"dead.2"* && "$line" == *"dead.3"* ]]
}

@test "005 C3: zero eligible corpses ⇒ zero kill invocations" {
    fixture_row live.1 44 1 200 /tmp
    fixture_row recent.1 45 0 100 /tmp "ended=$(date +%s)" "exit_code=0"
    ZS_REAP_WAIT=1 run zs --list --only=local
    [[ "$output" == *"recent.1"* ]]                    # young corpse renders dim
    [ "$(grep -c '^zmx kill' "$ZMX_FAKE_LOG")" -eq 0 ]
}

@test "005 C3: a FAILING kill changes nothing operator-visible" {
    fixture_row dead.1 41 0 100 /tmp "ended=1000" "exit_code=0"
    fixture_row live.1 44 1 200 /tmp
    ZS_REAP_WAIT=1 ZMX_FAKE_KILL_RC=1 run zs --list --only=local
    out_fail="$output"; st_fail="$status"
    ZS_REAP_WAIT=1 run zs --list --only=local
    [ "$out_fail" = "$output" ]
    [ "$st_fail" = "$status" ]
    [[ "$output" != *"dead.1"* ]]                      # suppressed both times
}

@test "005 C1 guard: a render WITH a reap batch still scans exactly once" {
    fixture_row dead.1 41 0 100 /tmp "ended=1000" "exit_code=0"
    fixture_row live.1 44 1 200 /tmp
    ZS_REAP_WAIT=1 run zs --list --only=local
    [ "$(grep -c '^zmx list' "$ZMX_FAKE_LOG")" -eq 1 ]
}
