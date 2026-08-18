#!/usr/bin/env bats
# zp: sibling-base derivation, pinned-split sibling protocol (FR-001..003),
# fallbacks. The mirror defect: a pinned split must NEVER run `ssh host.sess`.
load helpers

setup() { setup_shims; }

# Fake kitty tab: window 1 is me (plain shell), window 2 runs `zmx attach $1`.
make_kitty_tab() {
    cat > "$BATS_TEST_TMPDIR/kls.json" <<EOF
[{"tabs":[{"windows":[
  {"id":1,"foreground_processes":[{"cmdline":["bash"]}]},
  {"id":2,"foreground_processes":[{"cmdline":["/opt/homebrew/bin/zmx","attach","$1"]}]}
]}]}]
EOF
    export KITTEN_FAKE_LS="$BATS_TEST_TMPDIR/kls.json"
    export KITTY_WINDOW_ID=1 KITTY_LISTEN_ON=unix:/tmp/fake-kitty-sock
}

@test "local sibling: split follows the tab's project base" {
    make_kitty_tab proj.1
    fixture_row proj.1 11 1 100 /tmp
    run zp
    assert_log_has "zmx attach proj.2" "$ZMX_FAKE_LOG"
    assert_log_lacks "ssh" "$ZMX_FAKE_LOG"
}

@test "numbered wrapper: split dials the bare host, no remote query" {
    make_kitty_tab @myhost.3
    fixture_row @myhost.3 11 1 100 /tmp "cmd=ssh myhost"
    run zp
    assert_log_has "zmx attach @myhost.4 ssh myhost" "$ZMX_FAKE_LOG"
    assert_log_lacks "BatchMode=yes" "$SSH_FAKE_LOG"
}

@test "pinned wrapper: split queries host and pins the sibling (NOT a mirror)" {
    make_kitty_tab @myhost.dev
    fixture_row @myhost.dev 11 1 100 /tmp "cmd=ssh myhost.dev"
    export SSH_FAKE_STDOUT="dev.2"
    run zp
    assert_log_has "zn -n dev" "$SSH_FAKE_LOG"
    assert_log_has "BatchMode=yes" "$SSH_FAKE_LOG"
    assert_log_has "zmx attach @myhost.dev.2 ssh myhost.dev.2" "$ZMX_FAKE_LOG"
    # the defect: another client on the SAME remote session
    assert_log_lacks "zmx attach @myhost.dev.1 ssh myhost.dev" "$ZMX_FAKE_LOG"
}

@test "pinned wrapper: query failure falls back to a plain host connection" {
    make_kitty_tab @myhost.dev
    fixture_row @myhost.dev 11 1 100 /tmp "cmd=ssh myhost.dev"
    export SSH_FAKE_RC=255 SSH_FAKE_STDOUT=""
    run zp
    assert_log_has "zmx attach @myhost.1 ssh myhost" "$ZMX_FAKE_LOG"
}

@test "pinned wrapper with dotted remote session name" {
    make_kitty_tab @myhost.dev.boot
    fixture_row @myhost.dev.boot 11 1 100 /tmp "cmd=ssh myhost.dev.boot"
    export SSH_FAKE_STDOUT="dev.boot.2"
    run zp
    assert_log_has "zn -n dev.boot" "$SSH_FAKE_LOG"
    assert_log_has "zmx attach @myhost.dev.boot.2 ssh myhost.dev.boot.2" "$ZMX_FAKE_LOG"
}

@test "split from a pinned SIBLING strips its numeric tail first" {
    make_kitty_tab @myhost.dev.2
    fixture_row @myhost.dev.2 11 1 100 /tmp "cmd=ssh myhost.dev.2"
    export SSH_FAKE_STDOUT="dev.3"
    run zp
    assert_log_has "zn -n dev" "$SSH_FAKE_LOG"
    assert_log_has "zmx attach @myhost.dev.3 ssh myhost.dev.3" "$ZMX_FAKE_LOG"
}

@test "no kitty: falls back to cwd naming" {
    mkdir -p "$BATS_TEST_TMPDIR/myproj" && cd "$BATS_TEST_TMPDIR/myproj"
    run zp
    assert_log_has "zmx attach myproj.1" "$ZMX_FAKE_LOG"
}

# ── spec 003 US2: choose the locality explicitly (FR-009) ───────────────────

@test "003: zp --host makes an @host.N wrapper pane, skipping sibling detection" {
    make_kitty_tab proj.1          # sibling says proj — --host must win
    run zp --host ws15
    assert_log_has "zmx attach @ws15.1 ssh ws15" "$ZMX_FAKE_LOG"
    assert_log_lacks "attach proj" "$ZMX_FAKE_LOG"
}

@test "003: zp --local forces a cwd-named local pane even in an @host tab" {
    make_kitty_tab @myhost.1       # sibling is a wrapper — --local must win
    mkdir -p "$BATS_TEST_TMPDIR/myproj" && cd "$BATS_TEST_TMPDIR/myproj"
    run zp --local
    assert_log_has "zmx attach myproj.1" "$ZMX_FAKE_LOG"
    assert_log_lacks "ssh" "$ZMX_FAKE_LOG"
}

@test "003: bare zp is unchanged by the new flags (same-context split)" {
    make_kitty_tab @myhost.1
    fixture_row @myhost.1 11 1 100 /tmp "cmd=ssh myhost"
    run zp
    assert_log_has "zmx attach @myhost.2 ssh myhost" "$ZMX_FAKE_LOG"
}

@test "003: zp --host without an argument degrades to a plain shell, not death" {
    run zp --host
    [[ "$output" == *"--host needs a host"* ]]
}


# ── 004 US5: splits from a remote pane stay on that host ─────────────────────

# Tab where the SOURCE pane shows its `ssh` child — what a live wrapper pane
# actually looks like once connected — rather than `zmx attach`.
make_kitty_tab_ssh() {
    printf '%s\n' '[{"tabs":[{"active_window_history":[2,1],"windows":[' \
      '{"id":1,"foreground_processes":[{"cmdline":["bash"]}]},' \
      "{\"id\":2,\"foreground_processes\":[{\"cmdline\":[\"ssh\",\"$1\"]}]}" \
      ']}]}]' > "$BATS_TEST_TMPDIR/kls.json"
    export KITTEN_FAKE_LS="$BATS_TEST_TMPDIR/kls.json"
    export KITTY_WINDOW_ID=1 KITTY_LISTEN_ON=unix:/tmp/fake-kitty-sock
}

@test "004 US5: split from a wrapper pane showing its ssh child stays on that host" {
    # regression: this fell through to local cwd naming, so splitting from
    # @mac14.home.1 produced a LOCAL home.N on the wrong machine
    make_kitty_tab_ssh mac14.home.1
    SSH_FAKE_STDOUT="home.2" run zp
    assert_log_has "zmx attach @mac14.home.2 ssh mac14.home.2" "$ZMX_FAKE_LOG"
}

@test "004 US5: the most recently active pane wins as the split source" {
    printf '%s\n' '[{"tabs":[{"active_window_history":[2,3],"windows":[' \
      '{"id":1,"foreground_processes":[{"cmdline":["bash"]}]},' \
      '{"id":2,"foreground_processes":[{"cmdline":["/usr/bin/zmx","attach","@wrong.home.1"]}]},' \
      '{"id":3,"foreground_processes":[{"cmdline":["/usr/bin/zmx","attach","@right.home.1"]}]}' \
      ']}]}]' > "$BATS_TEST_TMPDIR/kls.json"
    export KITTEN_FAKE_LS="$BATS_TEST_TMPDIR/kls.json"
    export KITTY_WINDOW_ID=1 KITTY_LISTEN_ON=unix:/tmp/fake-kitty-sock
    SSH_FAKE_STDOUT="home.2" run zp
    assert_log_has "zmx attach @right.home.2 ssh right.home.2" "$ZMX_FAKE_LOG"
    assert_log_lacks "@wrong" "$ZMX_FAKE_LOG"
}

@test "004 US5: a local pane is unaffected (still cwd/theme naming)" {
    make_kitty_tab proj.1
    fixture_row proj.1 11 1 100 /tmp
    run zp
    assert_log_has "zmx attach proj.2" "$ZMX_FAKE_LOG"
    assert_log_lacks "ssh" "$ZMX_FAKE_LOG"
}
