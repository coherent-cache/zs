#!/usr/bin/env bats
# Version-probe cache — a daemon is probed at most once in its lifetime.
#
# Why: `zmx get` against a pre-0.7.0 daemon fails only after a ~1s client
# timeout (measured live: 1011ms, every try), and the marker probe used to run
# per unlabelled session PER RENDER — ws15 carried 44 stale daemons, making
# every picker open ~44s late. The verdict is now cached as "name:pid ok|old"
# in ~/.cache/zs/verprobe; a recreated session gets a new pid, so the cache
# can never go stale on an upgrade.
load helpers

setup() { setup_shims; }

@test "verprobe: an old daemon still gets its ⚠0.6 marker on the FIRST render" {
    fixture_row oldone 12 0 200 /tmp
    ZMX_FAKE_OLD="oldone" run zs --list --only=local
    [[ "$output" == *"0.6"* ]]
}

@test "verprobe: the second render answers from cache — zero zmx get calls" {
    fixture_row oldone 12 0 200 /tmp
    ZMX_FAKE_OLD="oldone" run zs --list --only=local
    : > "$ZMX_FAKE_LOG"
    ZMX_FAKE_OLD="oldone" run zs --list --only=local
    [[ "$output" == *"0.6"* ]]                         # marker survives...
    [ "$(grep -c '^zmx get' "$ZMX_FAKE_LOG")" -eq 0 ]  # ...without a re-probe
}

@test "verprobe: a healthy unlabelled daemon is also probed exactly once" {
    fixture_row fine.1 11 0 100 /tmp
    run zs --list --only=local
    : > "$ZMX_FAKE_LOG"
    run zs --list --only=local
    [[ "$output" != *"0.6"* ]]
    [ "$(grep -c '^zmx get' "$ZMX_FAKE_LOG")" -eq 0 ]
}

@test "verprobe: a recreated session (same name, NEW pid) is re-probed" {
    mkdir -p "$HOME/.cache/zs"
    printf 'fresh.1:11 old\n' > "$HOME/.cache/zs/verprobe"
    fixture_row fresh.1 99 0 300 /tmp        # new daemon: pid 11 -> 99
    run zs --list --only=local               # fake get succeeds -> 0.7.0
    [[ "$output" != *"0.6"* ]]
    grep -q '^zmx get fresh.1' "$ZMX_FAKE_LOG"
}

@test "verprobe: prune drops cache entries for daemons no longer listed" {
    mkdir -p "$HOME/.cache/zs"
    printf 'gone.1:44 old\n' > "$HOME/.cache/zs/verprobe"
    fixture_row here.1 11 0 100 /tmp
    run zs --list --only=local               # here.1 is a miss -> probe+prune
    ! grep -q 'gone.1' "$HOME/.cache/zs/verprobe"
    grep -q '^here.1:11 ok' "$HOME/.cache/zs/verprobe"
}

@test "verprobe: labelled sessions never touch the probe or the cache" {
    fixture_row tagged.1 11 0 100 /tmp "role=shell"
    run zs --list --only=local
    [ "$(grep -c '^zmx get' "$ZMX_FAKE_LOG")" -eq 0 ]
    [ ! -e "$HOME/.cache/zs/verprobe" ]
}
