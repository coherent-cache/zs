#!/usr/bin/env bats
# zn: numbering, corpse-name blocking, scripting stdout contract (FR-013),
# @-theme refusal (FR-006, v3).
load helpers

setup() { setup_shims; }

@test "zn -n picks 1 + highest existing number" {
    fixture_row dev.1 11 0 100 /tmp
    fixture_row dev.3 12 0 200 /tmp
    run zn -n dev
    [ "$status" -eq 0 ]
    [ "$output" = "dev.4" ]
}

@test "zn -n starts at .1 for a fresh theme" {
    run zn -n fresh
    [ "$output" = "fresh.1" ]
}

@test "corpse names still block reuse (poisoned until killed)" {
    fixture_row dead.2 11 0 100 /tmp "ended=$(($(date +%s) - 3600))" "exit_code=0"
    run zn -n dead
    [ "$output" = "dead.3" ]
}

@test "zn -r prints EXACTLY the bare session name on stdout" {
    run zn burst -r sleep 5
    [ "$status" -eq 0 ]
    [ "$output" = "burst.1" ]
    assert_log_has "zmx run burst.1 -d sleep 5" "$ZMX_FAKE_LOG"
}

@test "zn -l lists theme sessions" {
    fixture_row dev.1 11 0 100 /tmp
    run zn -l dev
    [ "$output" = "dev.1" ]
}

@test "v3: zn refuses to attach an @ theme" {
    run zn @myhost
    [ "$status" -eq 2 ]
    [[ "$output" == *"zs"* ]]
    assert_log_lacks "zmx attach" "$ZMX_FAKE_LOG"
}

@test "v3: zn -r refuses an @ theme" {
    run zn @myhost -r sleep 5
    [ "$status" -eq 2 ]
    assert_log_lacks "zmx run" "$ZMX_FAKE_LOG"
}

@test "v3: zn -n and -l still allow @ themes (wrapper numbering)" {
    fixture_row @myhost.1 11 0 100 /tmp
    run zn -n @myhost
    [ "$status" -eq 0 ]
    [ "$output" = "@myhost.2" ]
    run zn -l @myhost
    [ "$status" -eq 0 ]
    [ "$output" = "@myhost.1" ]
}
