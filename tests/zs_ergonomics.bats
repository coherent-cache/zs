#!/usr/bin/env bats
# Spec 002 (zs picker ergonomics): locality banding + coupled host recency
# (US5), @-surfacing + literal ctrl-n + completion + exact toggle (US1),
# lazy drill fallback (US4), and marked multi-kill (US3). Existing suites
# cover the unchanged paths.
load helpers

setup() { setup_shims; }

log_has_exact() { grep -qxF -- "$1" "$ZMX_FAKE_LOG" || { echo "expected exact '$1' in zmx log:"; cat "$ZMX_FAKE_LOG"; return 1; }; }

# ── US5: locality bands + filter ──────────────────────────────────────────────

@test "US5: local session and @remote wrapper land in separate bands" {
    fixture_row proj.1  11 1 200 /tmp
    fixture_row @web.1  12 1 300 /tmp "cmd=ssh web"
    printf 'Host web\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --list
    # local session sorts (band 1) above the remote wrapper (band 3) above host
    local li ri hi
    li=$(printf '%s\n' "$output" | grep -n 's:proj.1'  | cut -d: -f1)
    ri=$(printf '%s\n' "$output" | grep -n 's:@web.1'  | cut -d: -f1)
    hi=$(printf '%s\n' "$output" | grep -n 'h:web'     | cut -d: -f1)
    [ "$li" -lt "$ri" ] && [ "$ri" -lt "$hi" ]
}

@test "US5: --only=local shows local sessions, no @wrappers, no hosts" {
    fixture_row proj.1 11 1 200 /tmp
    fixture_row @web.1 12 1 300 /tmp "cmd=ssh web"
    printf 'Host web\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --list --only=local
    [[ "$output" == *"s:proj.1"* ]]
    [[ "$output" != *"s:@web.1"* ]]
    [[ "$output" != *"h:web"* ]]
}

@test "US5: --only=remote shows @wrappers + hosts, no local session" {
    fixture_row proj.1 11 1 200 /tmp
    fixture_row @web.1 12 1 300 /tmp "cmd=ssh web"
    printf 'Host web\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --list --only=remote
    [[ "$output" == *"s:@web.1"* ]]
    [[ "$output" == *"h:web"* ]]
    [[ "$output" != *"s:proj.1"* ]]
}

# ── US5/FR-013: host recency coupled to session recency ───────────────────────

@test "US5: an attached @host wrapper floats its host above an idle host (SC-008)" {
    # ws105 has an ATTACHED wrapper (clients=1 -> NOW); zzz has nothing.
    fixture_row @ws105.bld 20 1 100 /tmp "cmd=ssh ws105.bld"
    printf 'Host ws105\n  HostName 1.1.1.1\nHost zzz\n  HostName 2.2.2.2\n' > "$HOME/.ssh/config"
    run zs --list --only=remote
    local hp zz
    hp=$(printf '%s\n' "$output" | grep -n 'h:ws105' | cut -d: -f1)
    zz=$(printf '%s\n' "$output" | grep -n 'h:zzz'   | cut -d: -f1)
    [ -n "$hp" ] && [ -n "$zz" ] && [ "$hp" -lt "$zz" ]
}

@test "US5: --list makes no ssh call for grouping/recency (network-free open, SC-007)" {
    fixture_row @ws105.bld 20 1 100 /tmp "cmd=ssh ws105.bld"
    printf 'Host ws105\n  HostName 1.1.1.1\n' > "$HOME/.ssh/config"
    : > "$SSH_FAKE_LOG"
    run zs --list
    # _hosts_dedup uses `ssh -G` (config resolution), which is local config, not
    # a network session; assert NO remote command form `ssh host 'cmd'` ran.
    ! grep -qE "^ssh [^-].* (zmx|true)" "$SSH_FAKE_LOG"
}

# ── US1: surfacing, literal ctrl-n, completion, exact toggle ──────────────────

@test "US1: actionhint names the @connect for a known-host query" {
    printf 'Host ws15\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --actionhint "ws15.mesh.1"
    [[ "$output" == *"connect @ws15.mesh.1"* ]]
    [[ "$output" == *"create LOCAL ws15.mesh.1"* ]]
}

@test "US1: actionhint on a non-host query does not offer an @connect" {
    printf 'Host ws15\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --actionhint "scratch"
    [[ "$output" != *"connect @"* ]]
    [[ "$output" == *"create LOCAL scratch"* ]]
}

@test "US1/FR-001: ctrl-n stays literal — a host-like name creates a LOCAL session, no ssh" {
    printf 'Host ws15\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    # ctrl-n emits s:QUERY; run_choice on s:ws15.mesh.1 must attach it LOCALLY
    run zs --pick-test "s:ws15.mesh.1"
    log_has_exact "zmx attach ws15.mesh.1"
    assert_log_lacks "ssh" "$ZMX_FAKE_LOG"
}

@test "US1: complete turns a host row into the @host. prefix, a session into its name" {
    run zs --complete "h:ws15"
    [ "$output" = "change-query(@ws15)" ]
    run zs --complete "s:proj.1"
    [ "$output" = "change-query(proj.1)" ]
}

@test "US1: tab honors the TYPED host over the fuzzy-highlighted row" {
    printf 'Host ws15\n  HostName 1.1.1.1\nHost ws105\n  HostName 2.2.2.2\n' > "$HOME/.ssh/config"
    # typed ws15.mes while @ws105.mesh.1 is highlighted: ws15 must win
    run zs --complete "s:@ws105.mesh.1" "ws15.mes"
    [ "$output" = "change-query(@ws15.mes)" ]
    # bare typed host gets the trailing dot, ready for a session
    run zs --complete "s:@ws105.mesh.1" "ws15"
    [ "$output" = "change-query(@ws15)" ]
    # @-typed and exact-prefixed forms are honored too
    run zs --complete "s:@ws105.mesh.1" "'@ws15.c"
    [ "$output" = "change-query(@ws15.c)" ]
    # a non-host query falls back to row completion
    run zs --complete "s:@ws105.mesh.1" "mes"
    [ "$output" = "change-query(@ws105.mesh.1)" ]
}

@test "T028: hint tells the truth — enter reflects the HIGHLIGHTED row, diverging typed host is routed" {
    printf 'Host ws15\n  HostName 1.1.1.1\nHost ws105\n  HostName 2.2.2.2\n' > "$HOME/.ssh/config"
    # typed ws15.mes, highlighted @ws105.mesh.1: enter must be described as the
    # highlighted attach, never as "connect @ws15.mes"
    run zs --actionhint "ws15.mes" "s:@ws105.mesh.1"
    [[ "$output" == *"enter: attach @ws105.mesh.1"* ]]
    [[ "$output" != *"enter: connect @ws15"* ]]
    [[ "$output" == *"typed @ws15.mes"* ]]      # the typed intent is routed, visibly
    # same host highlighted (a @ws15 wrapper): no divergence callout
    run zs --actionhint "ws15" "s:@ws15.cn"
    [[ "$output" == *"enter: attach @ws15.cn"* ]]
    [[ "$output" != *"typed @"* ]]
    # no matching row: enter acts on the classified query
    run zs --actionhint "ws15.mes" ""
    [[ "$output" == *"enter: connect @ws15.mes"* ]]
}

@test "T029: bare-host hint states both enter and ctrl-n" {
    printf 'Host ws15\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --actionhint "ws15" ""
    [[ "$output" == *"ssh ws15 (remote resume/create; @ws15 = local wrapper)"* ]]
    [[ "$output" == *"ctrl-n: create LOCAL ws15"* ]]
}

@test "T030: within a host cluster, attached wrappers rank above detached" {
    # same host web -> same cluster recency; detached is NEWER but attached wins
    fixture_row @web.old 11 1 100 /tmp "cmd=ssh web"
    fixture_row @web.new 12 0 900 /tmp "cmd=ssh web"
    printf 'Host web\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --list --only=remote
    local a d
    a=$(printf '%s\n' "$output" | grep -n 's:@web.old' | cut -d: -f1)
    d=$(printf '%s\n' "$output" | grep -n 's:@web.new' | cut -d: -f1)
    [ -n "$a" ] && [ -n "$d" ] && [ "$a" -lt "$d" ]
}

@test "T032: preview falls back to raw history when --vt is unsupported" {
    fixture_row proj.1 11 0 100 /tmp
    ZMX_FAKE_NO_VT=1 run zs --preview "s:proj.1"
    [[ "$output" == *"fake scrollback for proj.1"* ]]
}

@test "US1: exacttoggle adds then strips the leading ' exact token" {
    run zs --exacttoggle "ws15"
    [ "$output" = "'ws15" ]
    run zs --exacttoggle "'ws15"
    [ "$output" = "ws15" ]
}

@test "US1: enter on an @-led typed query is a wrapper connect, never ssh '@name'" {
    printf 'Host myhost\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    # tab-completed @myhost.dev + enter (no matching row) -> q: token
    run zs --pick-test "q:@myhost.dev"
    log_has_exact "zmx attach @myhost.dev ssh myhost.dev"
    ! grep -qF "ssh @" "$ZMX_FAKE_LOG"
    # bare @myhost + enter behaves like picking the host row (fresh wrapper)
    : > "$ZMX_FAKE_LOG"
    run zs --pick-test "q:@myhost"
    log_has_exact "zmx attach @myhost.1 ssh myhost"
}

# ── US4: lazy drill with non-zmx fallback ─────────────────────────────────────

@test "US4: drillbind on a host row reloads the picker with that host's sessions" {
    run zs --drillbind "h:myhost"
    [[ "$output" == *"reload(zs --drill-rows h:myhost)"* ]]
    # non-host rows are a no-op (no reload)
    run zs --drillbind "s:proj.1"
    [ -z "$output" ]
}

@test "US4: drill-rows lists a zmx host's remote sessions as pickable r: rows" {
    printf 'Host myhost\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    SSH_FAKE_STDOUT=$'  name=dev\tpid=1\tclients=0\tcreated=1\tstart_dir=/x' run zs --drill-rows "h:myhost"
    [[ "$output" == *"r:myhost.dev"* ]]
    [[ "$output" == *"○"* ]]
    # that row, chosen, attaches via the ordinary @wrapper enter path
    run zs --pick-test "r:myhost.dev"
    log_has_exact "zmx attach @myhost.dev ssh myhost.dev"
}

@test "US4: preview of a drill row fetches the REMOTE session history over ssh" {
    printf 'Host myhost\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    SSH_FAKE_STDOUT="remote scrollback line" run zs --preview "r:myhost.dev"
    [[ "$output" == *"remote scrollback line"* ]]
    grep -q "history dev" "$SSH_FAKE_LOG"       # went over ssh, not local zmx
    assert_log_lacks "history" "$ZMX_FAKE_LOG"  # no local zmx history call
}

@test "US4: killing a drill row kills the REMOTE session and reaps the local wrapper" {
    printf 'Host myhost\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --kill-multi "r:myhost.dev"
    grep -q "kill dev" "$SSH_FAKE_LOG"          # remote kill over ssh
    log_has_exact "zmx kill @myhost.dev"        # local wrapper reaped
}

@test "US4: esc inside a drill goes back to the list; at top level it aborts" {
    FZF_PROMPT="⇲ myhost> " run zs --escbind
    [[ "$output" == *"reload(zs --list --only=all)"* ]]
    FZF_PROMPT="zmx> " run zs --escbind
    [ "$output" = "abort" ]
}

@test "US4: ctrl-x reload inside a drill view stays in the drill (list --only=current)" {
    printf 'Host myhost\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    SSH_FAKE_STDOUT=$'  name=dev\tpid=1\tclients=0\tcreated=1\tstart_dir=/x' FZF_PROMPT="⇲ myhost> " run zs --list --only=current
    [[ "$output" == *"r:myhost.dev"* ]]
    [[ "$output" != *"h:myhost"$'\t'* ]]  # drill rows, not the full host list
}

@test "US4: drill renders remote CORPSES dimmed, like the top level" {
    printf 'Host myhost\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    SSH_FAKE_STDOUT=$'  name=dead\tpid=1\tclients=0\tcreated=1\tstart_dir=/x\tended=2\texit_code=0' \
        run zs --drill-rows "h:myhost"
    [[ "$output" == *"r:myhost.dead"* ]]      # still killable/reapable
    [[ "$output" == *"ended on myhost"* ]]    # but clearly marked dead
    [[ "$output" != *"⇲ on myhost"* ]]        # not presented as attachable
}

@test "US4: drill-rows with no remote sessions yields one plain-connect row" {
    printf 'Host myhost\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    # default fake: rc=0 with empty stdout. Pre-004 this rendered the same
    # "no zmx / unreachable" text as a dead host; spec 004 FR-002 separates the
    # classes, and rc=0 + no output means REACHABLE with zero sessions — an
    # ordinary empty drill, not an error. (no-zmx / auth / unreachable are
    # covered in zs_errors.bats.)
    run zs --drill-rows "h:myhost"
    [[ "$output" == *"h:myhost"* ]]
    [[ "$output" == *"no sessions"* ]]
    [[ "$output" != *"no zmx"* ]]
    # and that fallback row is the ordinary host connect — post-003 that is a
    # ONE-LAYER plain ssh (US3), not a local wrapper
    run zs --pick-test "h:myhost"
    grep -qxF "ssh myhost" "$SSH_FAKE_LOG"
    ! grep -q "zmx attach @myhost" "$ZMX_FAKE_LOG"
}

# ── US3: marked multi-kill ────────────────────────────────────────────────────

@test "US3: space is actually bound to mark (toggle+down), not left typing a space" {
    grep -q -- "--bind 'space:toggle+down'" "$ROOT/bin/zs"
    grep -q -- "--multi" "$ROOT/bin/zs"
}

@test "US3: kill-multi kills every marked session and ignores host tokens" {
    run zs --kill-multi "s:a.1" "s:b.2" "h:web"
    log_has_exact "zmx kill a.1"
    log_has_exact "zmx kill b.2"
    ! grep -qF "zmx kill web" "$ZMX_FAKE_LOG"
}

# ── spec 003 US3 [Δ002]: host-row vs explicit-@ coherence (FR-011/012/013) ───

@test "003: host row = one-layer ssh; typed @host = the tagged local wrapper" {
    printf 'Host ws15\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --pick-test "h:ws15"
    grep -qxF "ssh ws15" "$SSH_FAKE_LOG"        # exactly what `ssh ws15` does
    ! grep -q "zmx attach" "$ZMX_FAKE_LOG"      # no local wrapper layer
    : > "$SSH_FAKE_LOG"; : > "$ZMX_FAKE_LOG"
    run zs --pick-test "q:@ws15"                # the explicit wrapper request
    grep -q "zmx attach @ws15.1 ssh ws15" "$ZMX_FAKE_LOG"   # @-tagged, visible
}

# ── 004 US4: empty results explain themselves (FR-006) ───────────────────────

@test "004: a zero-match query says nothing matched, not just an empty list" {
    fixture_row alpha 11 0 100 /tmp
    # empty {1} = fzf found no row; query is non-empty
    run zs --actionhint "zzzznomatch" ""
    [[ "$output" == *"no match"* ]]
    [[ "$output" == *"zzzznomatch"* ]]
}

@test "004: zero-match names the likely cause — no ssh host by that name here" {
    printf 'Host other\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --actionhint "mac14" ""
    [[ "$output" == *"no ssh host by that name on this machine"* ]]
}

@test "004: a query that DOES match a row still describes enter normally" {
    fixture_row alpha 11 0 100 /tmp
    run zs --actionhint "alpha" "s:alpha"
    [[ "$output" == *"enter: attach alpha"* ]]
    [[ "$output" != *"no match"* ]]
}
