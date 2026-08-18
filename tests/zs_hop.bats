#!/usr/bin/env bats
# spec 003 US1 — zs --hop: in-session switch hop.
# The hop is the ONE entry point exempt from the $ZMX_SESSION guard: it runs
# the picker inside a session, writes the selection to the per-session hop
# handoff and detaches; the enclosing attach loop re-attaches the target
# (switch model — depth stays 1, origin keeps running detached).

load helpers

setup() {
    setup_shims
    # default fake fzf (0.44) fails the version gate -> plain-menu fallback,
    # so selections can be piped on stdin
    ln -sf "$ROOT/tests/fakes/fzf" "$HOME/.local/bin/fzf"
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"; mkdir -p "$XDG_RUNTIME_DIR"
}

# ── guard exemption (T004) ──────────────────────────────────────────────────

@test "guard: pick/direct still refuse inside a session" {
    ZMX_SESSION=dev.1 run zs other
    [ "$status" -ne 0 ]
    [[ "$output" == *'detach first'* ]]
}

@test "guard: --hop is exempt — runs the picker inside a session" {
    fixture_row dev.1 11 1 100 /tmp
    fixture_row bld.2 12 0 200 /tmp
    ZMX_SESSION=dev.1 run zs --hop <<< $'\n'   # empty selection: cancelled
    [[ "$output" != *'detach first'* ]]
    [[ "$output" == *'plain menu'* ]]          # the picker actually opened
}

# ── hop handoff + detach (T005) ─────────────────────────────────────────────

@test "hop: selection writes the handoff token and detaches (never nested attach)" {
    fixture_row dev.1 11 1 100 /tmp
    fixture_row bld.2 12 0 200 /tmp
    ZMX_SESSION=dev.1 run zs --hop <<< 'bld.2'
    [ "$status" -eq 0 ]
    [ -f "$XDG_RUNTIME_DIR/zs-hop.dev.1" ]
    [ "$(cat "$XDG_RUNTIME_DIR/zs-hop.dev.1")" = "s:bld.2" ]
    grep -qx 'zmx detach' "$ZMX_FAKE_LOG"
    ! grep -q 'zmx attach' "$ZMX_FAKE_LOG"     # switch, not nest
}

@test "hop: free-form query token lands in the handoff (q:)" {
    fixture_row dev.1 11 1 100 /tmp
    ZMX_SESSION=dev.1 run zs --hop <<< 'brandnew'
    [ "$(cat "$XDG_RUNTIME_DIR/zs-hop.dev.1")" = "q:brandnew" ]
    grep -qx 'zmx detach' "$ZMX_FAKE_LOG"
}

@test "hop: selecting the current session is a graceful no-op" {
    fixture_row dev.1 11 1 100 /tmp
    fixture_row bld.2 12 0 200 /tmp
    ZMX_SESSION=dev.1 run zs --hop <<< 'dev.1'
    [ "$status" -eq 0 ]
    [ ! -e "$XDG_RUNTIME_DIR/zs-hop.dev.1" ]
    ! grep -q 'zmx detach' "$ZMX_FAKE_LOG"
}

@test "hop: outside a session behaves like the normal picker (attach, no handoff)" {
    fixture_row bld.2 12 0 200 /tmp
    run zs --hop <<< 'bld.2'
    grep -q 'zmx attach bld.2' "$ZMX_FAKE_LOG"
    ! grep -q 'zmx detach' "$ZMX_FAKE_LOG"
    [ -z "$(ls "$XDG_RUNTIME_DIR" 2>/dev/null)" ]
}

# ── the consuming switch loop in attach_run (T006–T008) ─────────────────────

@test "loop: attach_run re-attaches the handoff target after detach (switch chain)" {
    fixture_row alpha 11 0 100 /tmp
    fixture_row beta  12 0 200 /tmp
    printf 's:beta\n' > "$XDG_RUNTIME_DIR/zs-hop.alpha"
    run zs --pick-test s:alpha
    [ "$status" -ne 0 ] || true                # detached, not ended → rc from attach_run
    grep -q 'zmx attach alpha' "$ZMX_FAKE_LOG"
    grep -q 'zmx attach beta'  "$ZMX_FAKE_LOG"
    # order: alpha before beta
    [ "$(grep -n 'zmx attach alpha' "$ZMX_FAKE_LOG" | head -1 | cut -d: -f1)" \
      -lt "$(grep -n 'zmx attach beta' "$ZMX_FAKE_LOG" | head -1 | cut -d: -f1)" ]
    [ ! -e "$XDG_RUNTIME_DIR/zs-hop.alpha" ]   # consumed exactly once
}

@test "loop: no handoff file → attach_run behaves exactly as before (single attach)" {
    fixture_row alpha 11 0 100 /tmp
    run zs --pick-test s:alpha
    [ "$(grep -c 'zmx attach' "$ZMX_FAKE_LOG")" -eq 1 ]
}

@test "loop: empty/stale handoff is removed and ignored" {
    fixture_row alpha 11 0 100 /tmp
    : > "$XDG_RUNTIME_DIR/zs-hop.alpha"
    run zs --pick-test s:alpha
    [ "$(grep -c 'zmx attach' "$ZMX_FAKE_LOG")" -eq 1 ]
    [ ! -e "$XDG_RUNTIME_DIR/zs-hop.alpha" ]
}

# ── 004 US3: bare `zs` inside a session defaults to hop ──────────────────────

@test "004: bare zs inside a session WITHOUT a tty does not hop (agents/scripts)" {
    # bats gives no interactive tty, so this is the non-interactive path:
    # it must refuse to hop AND say why (never exit silently).
    ZMX_SESSION=alpha run zs
    [ "$status" -ne 0 ]
    [[ "$output" == *"not hopping"* ]]
    [[ "$output" == *"alpha"* ]]
}

@test "004: bare zs OUTSIDE a session is unchanged (no hop, normal picker path)" {
    # stdin from /dev/null: with the old fake fzf this falls through to the
    # plain-menu fallback, whose `read` would otherwise block the suite.
    run bash -c 'zs </dev/null'
    [[ "$output" != *"not hopping"* ]]
}

@test "004: zs NAME inside a session explains instead of nesting" {
    ZMX_SESSION=alpha run zs somename
    [ "$status" -ne 0 ]
    [[ "$output" == *"nest"* ]]
    [[ "$output" == *"--hop"* ]]
}

@test "004: explicit --hop still works regardless of tty" {
    fixture_row target 11 0 100 /tmp
    ZMX_SESSION=alpha run zs --hop
    # --hop is unconditional: it must NOT hit the non-interactive guard
    [[ "$output" != *"not hopping"* ]]
}
