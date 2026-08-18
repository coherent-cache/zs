#!/usr/bin/env bats
# zs --list --only=current: ctrl-x's reload recovers the active view from
# FZF_PROMPT (fzf >=0.42); older fzf (unset) degrades to the all view (FR-004).
load helpers

setup() {
    setup_shims
    fixture_row sess.1 11 0 100 /tmp
    printf 'Host lab9\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
}

@test "only=current + local prompt: local session rows only" {
    FZF_PROMPT="local> " run zs --list --only=current
    [[ "$output" == *"s:sess.1"* ]]
    [[ "$output" != *"h:lab9"* ]]
}

@test "only=current + remote prompt: remote (hosts) rows only, no local session" {
    FZF_PROMPT="remote> " run zs --list --only=current
    [[ "$output" == *"h:lab9"* ]]
    [[ "$output" != *"s:sess.1"* ]]
}

@test "only=current + default prompt: all rows" {
    FZF_PROMPT="zmx> " run zs --list --only=current
    [[ "$output" == *"s:sess.1"* ]]
    [[ "$output" == *"h:lab9"* ]]
}

@test "only=current without FZF_PROMPT (old fzf): all rows, no error" {
    run zs --list --only=current
    [ "$status" -eq 0 ]
    [[ "$output" == *"s:sess.1"* ]]
    [[ "$output" == *"h:lab9"* ]]
}

@test "ctrl-x bind reloads with --only=current" {
    grep -q "ctrl-x:execute-silent(zs --kill-multi {+1})+clear-selection+reload(zs --list --only=current)" "$ROOT/bin/zs"
}
