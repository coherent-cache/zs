#!/usr/bin/env bats
# spec 004 US6 — sessions describe themselves (zmx 0.7.0 labels).
#
# Cost contract: labels ride the `zmx list` record we ALREADY fetch, so a
# render must not spawn a per-row `zmx get`. These tests assert behaviour and
# that cost property, because the previous version-marker implementation did
# spawn one probe per row on every render.
load helpers

setup() { setup_shims; }

@test "labels: parsed from the list record and shown as chips" {
    fixture_row proj.1 11 0 100 /tmp "role=job" "creator=zn"
    run zs --list --only=local
    [[ "$output" == *"role=job"* ]]
    [[ "$output" == *"creator=zn"* ]]
}

@test "labels: bookkeeping fields are NOT treated as labels" {
    # cmd=/ended=/exit_code= share the same tab-separated tail as real labels
    fixture_row agent.1 11 0 100 /tmp "cmd=agent --resume abc" "role=job"
    run zs --list --only=local
    [[ "$output" == *"role=job"* ]]
    [[ "$output" != *"cmd=agent"* ]]   # reserved key excluded by name
}

@test "labels: a session with labels renders NO stale-version marker" {
    # carrying a label proves a 0.7.0 daemon — no probe needed, no ⚠0.6
    fixture_row newone 11 0 100 /tmp "role=shell"
    run zs --list --only=local
    [[ "$output" != *"0.6"* ]]
}

@test "labels: an unlabelled session on an old daemon still gets the marker" {
    fixture_row oldone 12 0 200 /tmp
    ZMX_FAKE_OLD="oldone" run zs --list --only=local
    [[ "$output" == *"0.6"* ]]
}

@test "labels: rendering labelled rows spawns no per-row 'zmx get' (SC-007 cost)" {
    fixture_row a.1 11 0 100 /tmp "role=job"
    fixture_row b.1 12 0 200 /tmp "role=job"
    : > "$ZMX_FAKE_LOG"
    run zs --list --only=local
    [ "$(grep -c '^zmx get' "$ZMX_FAKE_LOG")" -eq 0 ]
}

@test "labels: --only=label:k=v scopes the list client-side" {
    fixture_row keep.1 11 0 100 /tmp "role=claude"
    fixture_row drop.1 12 0 200 /tmp "role=shell"
    run zs --list --only=label:role=claude
    [[ "$output" == *"s:keep.1"* ]]
    [[ "$output" != *"s:drop.1"* ]]
}

@test "labels: the filter never calls 'zmx ls --where' (a no-op in 0.7.0)" {
    fixture_row keep.1 11 0 100 /tmp "role=claude"
    : > "$ZMX_FAKE_LOG"
    run zs --list --only=label:role=claude
    ! grep -q -- '--where' "$ZMX_FAKE_LOG"
}

@test "labels: a new session is stamped with creator/role/cwd" {
    run zs --attach fresh.1
    grep -q '^zmx set fresh.1 creator=zs role=shell cwd=' "$ZMX_FAKE_LOG"
}

@test "labels: an @wrapper is stamped role=wrapper" {
    run zs --attach @host.1 ssh host
    grep -q '^zmx set @host.1 creator=zs role=wrapper' "$ZMX_FAKE_LOG"
}

@test "labels: stamping failure on an old daemon is silent and non-fatal" {
    ZMX_FAKE_OLD="fresh.2" run zs --attach fresh.2
    # the attach must still happen even though `zmx set` was rejected...
    grep -q '^zmx attach fresh.2' "$ZMX_FAKE_LOG"
    # ...and the daemon's label complaint must never reach the operator
    [[ "$output" != *"does not support labels"* ]]
    [[ "$output" != *"daemon too old"* ]]
}

# ── converge Phase 11 ────────────────────────────────────────────────────────

@test "T042: alt-y scopes the list by the highlighted row's role label (one action)" {
    ZMX_FAKE_LABELS="role=claude creator=zs" run zs --labelbind "s:proj.1"
    [[ "$output" == *"--only=label:role=claude"* ]]   # reloads scoped
    [[ "$output" == *"change-prompt"* ]]              # and marks the view
}

@test "T042: alt-y on a row with no role label explains instead of filtering blindly" {
    ZMX_FAKE_LABELS="" run zs --labelbind "s:proj.1"
    [[ "$output" == *"change-header"* ]]
    [[ "$output" == *"nothing to scope by"* ]]
    [[ "$output" != *"--only=label:"* ]]
}

@test "T042: alt-y on a non-session row says so" {
    run zs --labelbind "h:myhost"
    [[ "$output" == *"SESSION row"* ]]
}

@test "T043: a zp-initiated session is stamped creator=zp, not creator=zs" {
    ZS_CREATOR=zp run zs --attach split.1
    grep -q '^zmx set split.1 creator=zp role=shell' "$ZMX_FAKE_LOG"
}

@test "T043: a plain zs session still defaults to creator=zs" {
    run zs --attach plain.1
    grep -q '^zmx set plain.1 creator=zs role=shell' "$ZMX_FAKE_LOG"
}

# ── found live on mac14, 2026-08-03 ──────────────────────────────────────────
# zmx lists labels SORTED, so creator= renders before role= on every
# zs-stamped session. The filter used to grep "[k=v" — first chip position
# only — so --only=label:role=… (and alt-y) matched NOTHING zs itself created.

@test "labels: filter matches a label at ANY chip position (zmx sorts labels)" {
    fixture_row real.1 11 1 100 /tmp "creator=zs" "role=shell"
    run zs --list --only=label:role=shell
    [[ "$output" == *"s:real.1"* ]]
}

@test "labels: filter is delimiter-bounded — role=shell must not hit role=shellx" {
    fixture_row near.1 11 1 100 /tmp "creator=zs" "role=shellx"
    fixture_row hit.1  12 1 200 /tmp "creator=zs" "role=shell"
    run zs --list --only=label:role=shell
    [[ "$output" == *"s:hit.1"* ]]
    [[ "$output" != *"s:near.1"* ]]
}

@test "labels: filter still matches the first/only label" {
    fixture_row a.1 11 1 100 /tmp "creator=zn" "role=job"
    fixture_row b.1 12 1 200 /tmp "role=other"
    run zs --list --only=label:creator=zn
    [[ "$output" == *"s:a.1"* ]]
    [[ "$output" != *"s:b.1"* ]]
}

@test "labels: an ended session keeps its chips and stays findable by label" {
    # field order mirrors real zmx output: bookkeeping first, then labels
    now=$(date +%s)
    fixture_row done.1 11 0 "$now" /tmp "ended=$now" "exit_code=0" "creator=zn" "role=job"
    run zs --list --only=local
    [[ "$output" == *"(ended)"* ]]
    [[ "$output" == *"role=job"* ]]
    run zs --list --only=label:role=job
    [[ "$output" == *"s:done.1"* ]]
}
