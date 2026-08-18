#!/usr/bin/env bats
# fzf-less operation: the version gate (_fzf_ok), the plain-menu fallback
# picker, and the no-picker `zs NAME` direct mode. fzf must be a soft
# dependency — a box with distro fzf (< FZF_MIN) or none at all still gets
# the same rows and actions.
load helpers

setup() {
    setup_shims
    ln -sf "$ROOT/tests/fakes/fzf" "$HOME/.local/bin/fzf"
    printf 'Host myhost\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
}

log_has_exact() { grep -qxF -- "$1" "$ZMX_FAKE_LOG" || { echo "expected exact '$1' in zmx log:"; cat "$ZMX_FAKE_LOG"; return 1; }; }

# ── version gate ─────────────────────────────────────────────────────────────

@test "old fzf (0.44) falls back to the plain menu" {
    run bash -c 'echo | zs'
    [[ "$output" == *"plain menu"* ]]
}

@test "fzf at exactly FZF_MIN is used, not the fallback" {
    # gate passes -> the (fake) fzf runs and fails with 2 -> cancel, no menu
    FZF_FAKE_VERSION=0.59.0 run bash -c 'echo | zs'
    [ "$status" -eq 130 ]
    [[ "$output" != *"plain menu"* ]]
}

@test "unparseable fzf version falls back to the plain menu" {
    FZF_FAKE_VERSION=watermelon run bash -c 'echo | zs'
    [[ "$output" == *"plain menu"* ]]
}

# ── plain-menu fallback ──────────────────────────────────────────────────────

@test "menu lists session and host rows, numbered" {
    fixture_row dev.1 11 0 100 /tmp
    run bash -c 'echo | zs'
    [[ "$output" == *"1  dev.1"* ]]
    [[ "$output" == *"2  @myhost"* ]]
}

@test "picking a session row number attaches it" {
    fixture_row dev.1 11 0 100 /tmp
    run bash -c 'echo 1 | zs'
    log_has_exact "zmx attach dev.1"
}

@test "picking a host row number plain-connects (one layer, 003 US3)" {
    fixture_row dev.1 11 0 100 /tmp
    run bash -c 'echo 2 | zs'
    grep -qxF "ssh myhost" "$SSH_FAKE_LOG"
    ! grep -q "zmx attach @myhost" "$ZMX_FAKE_LOG"
}

@test "typing a listed session name attaches it" {
    fixture_row dev.1 11 0 100 /tmp
    run bash -c 'echo dev.1 | zs'
    log_has_exact "zmx attach dev.1"
}

@test "typing a free-form name is a query (local session)" {
    run bash -c 'echo scratch | zs'
    log_has_exact "zmx attach scratch"
    assert_log_lacks "ssh" "$ZMX_FAKE_LOG"
}

@test "typing user@host is a query (ssh wrapper)" {
    run bash -c 'echo alice@myhost | zs'
    log_has_exact "zmx attach @myhost.1 ssh alice@myhost"
}

@test "empty input cancels with 130 and attaches nothing" {
    fixture_row dev.1 11 0 100 /tmp
    run bash -c 'echo | zs'
    [ "$status" -eq 130 ]
    assert_log_lacks "attach" "$ZMX_FAKE_LOG"
}

@test "out-of-range number cancels with 130" {
    fixture_row dev.1 11 0 100 /tmp
    run bash -c 'echo 9 | zs'
    [ "$status" -eq 130 ]
    assert_log_lacks "attach" "$ZMX_FAKE_LOG"
}

# ── zs NAME direct mode (never needs fzf) ────────────────────────────────────

@test "zs NAME attaches an existing session by exact name" {
    fixture_row dev.1 11 0 100 /tmp
    run zs dev.1
    log_has_exact "zmx attach dev.1"
}

@test "zs HOST plain-connects like ssh HOST (one layer, 003 US3)" {
    run zs myhost
    grep -qxF "ssh myhost" "$SSH_FAKE_LOG"
    ! grep -q "zmx attach" "$ZMX_FAKE_LOG"
}

@test "zs @HOST is the explicit wrapper: resumes a detached one before creating" {
    fixture_row @myhost.1 11 0 100 /tmp "cmd=ssh myhost"
    run zs @myhost
    log_has_exact "zmx attach @myhost.1"
}

@test "zs NAME with an unknown word creates a local session" {
    run zs scratch
    log_has_exact "zmx attach scratch"
    assert_log_lacks "ssh" "$ZMX_FAKE_LOG"
}

@test "zs NAME refuses to nest inside a session" {
    ZMX_SESSION=dev.1 run zs other
    [ "$status" -eq 1 ]
    assert_log_lacks "attach" "$ZMX_FAKE_LOG"
}

@test "004: fallback menu explains an empty view (FR-010 parity)" {
    # setup() already shadows fzf with the 0.44 fake, so this IS the plain menu
    : > "$HOME/.ssh/config"
    run bash -c 'echo | zs'
    [[ "$output" == *"no sessions and no configured ssh hosts"* ]]
}

@test "004 US3: fallback honours the hop default — in-session without a tty refuses, with a reason" {
    # the hop default resolves in mode dispatch, BEFORE pick/fallback_pick, so
    # the plain menu inherits it; this locks that in (converge T044).
    ZMX_SESSION=alpha run bash -c 'echo | zs'
    [[ "$output" == *"not hopping"* ]]
    [[ "$output" != *"plain menu"* ]]   # never reached the fallback picker
}

@test "004 US3: explicit --hop is unaffected by the fallback path" {
    ZMX_SESSION=alpha run bash -c 'echo | zs --hop'
    [[ "$output" != *"not hopping"* ]]
}
