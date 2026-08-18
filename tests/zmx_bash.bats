#!/usr/bin/env bats
# spec 003 US1 — the switch loop on the SSH auto-attach path
# (shell/zmx.bash __zmx_attach_reap): after a detach, a hop handoff makes the
# loop attach the target instead of ending the connection.

load helpers

setup() {
    setup_shims
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"; mkdir -p "$XDG_RUNTIME_DIR"
    unset SSH_CONNECTION   # never trip the auto-attach while sourcing
}

# source the file and run the reap loop for one session name
reap() { bash -c "source '$ROOT/shell/zmx.bash'; __zmx_attach_reap '$1'"; }

@test "no handoff: single attach, then reap-check (pre-003 behavior)" {
    fixture_row dev.1 11 0 100 /tmp
    run reap dev.1
    [ "$(grep -c 'zmx attach' "$ZMX_FAKE_LOG")" -eq 1 ]
    grep -q 'zmx attach dev.1' "$ZMX_FAKE_LOG"
}

@test "s: handoff: loop re-attaches the target (switch)" {
    fixture_row dev.1 11 0 100 /tmp
    fixture_row bld.2 12 0 200 /tmp
    printf 's:bld.2\n' > "$XDG_RUNTIME_DIR/zs-hop.dev.1"
    run reap dev.1
    grep -q 'zmx attach dev.1' "$ZMX_FAKE_LOG"
    grep -q 'zmx attach bld.2' "$ZMX_FAKE_LOG"
    [ ! -e "$XDG_RUNTIME_DIR/zs-hop.dev.1" ]
}

@test "chained hops: dev.1 -> bld.2 -> lab.3" {
    printf 's:bld.2\n' > "$XDG_RUNTIME_DIR/zs-hop.dev.1"
    printf 's:lab.3\n' > "$XDG_RUNTIME_DIR/zs-hop.bld.2"
    run reap dev.1
    [ "$(grep -c 'zmx attach' "$ZMX_FAKE_LOG")" -eq 3 ]
    grep -q 'zmx attach lab.3' "$ZMX_FAKE_LOG"
    [ ! -e "$XDG_RUNTIME_DIR/zs-hop.bld.2" ]
}

@test "q: handoff: creates+attaches the named session" {
    printf 'q:brandnew\n' > "$XDG_RUNTIME_DIR/zs-hop.dev.1"
    run reap dev.1
    grep -q 'zmx attach brandnew' "$ZMX_FAKE_LOG"
}

@test "h: handoff: plain ssh to the host, then the loop ends" {
    printf 'h:ws15\n' > "$XDG_RUNTIME_DIR/zs-hop.dev.1"
    run reap dev.1
    grep -q '^ssh ws15$' "$SSH_FAKE_LOG"
    [ "$(grep -c 'zmx attach' "$ZMX_FAKE_LOG")" -eq 1 ]   # no re-attach after ssh
}

@test "empty handoff: removed, loop ends cleanly" {
    : > "$XDG_RUNTIME_DIR/zs-hop.dev.1"
    run reap dev.1
    [ "$status" -eq 0 ]
    [ "$(grep -c 'zmx attach' "$ZMX_FAKE_LOG")" -eq 1 ]
    [ ! -e "$XDG_RUNTIME_DIR/zs-hop.dev.1" ]
}
