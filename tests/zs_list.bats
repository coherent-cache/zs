#!/usr/bin/env bats
# zs --list: gutter parsing, row ordering, corpse rows, duplicate warning.
load helpers

setup() { setup_shims; NOW=$(date +%s); }

@test "gutter variants parse: 2-space and arrow rows both list" {
    fixture_row       alpha 11 0 100 /tmp
    fixture_row_arrow beta  12 1 200 /tmp
    run zs --list --only=local
    [ "$status" -eq 0 ]
    [[ "$output" == *"s:alpha"* ]]
    [[ "$output" == *"s:beta"* ]]
}

@test "row ordering: attached, detached (newest first), corpses last" {
    fixture_row old-detached 11 0 100 /tmp
    fixture_row new-detached 12 0 300 /tmp
    fixture_row attached     13 1 200 /tmp
    fixture_row corpse       14 0 400 /tmp "ended=$((NOW - 3600))" "exit_code=0"
    run zs --list --only=local
    [ "$status" -eq 0 ]
    a=$(grep -n "s:attached" <<<"$output" | cut -d: -f1)
    n=$(grep -n "s:new-detached" <<<"$output" | cut -d: -f1)
    o=$(grep -n "s:old-detached" <<<"$output" | cut -d: -f1)
    c=$(grep -n "s:corpse" <<<"$output" | cut -d: -f1)
    [ "$a" -lt "$n" ] && [ "$n" -lt "$o" ] && [ "$o" -lt "$c" ]
}

@test "corpse rows are marked ended and dimmed" {
    fixture_row corpse 14 0 400 /tmp "ended=$((NOW - 3600))" "exit_code=1"
    run zs --list --only=local
    [[ "$output" == *"(ended)"* ]]
}

@test "cmd= field on zmx-run-born sessions is harmless (first-class row)" {
    fixture_row agent.1 15 0 100 /tmp "cmd=agent --resume abc"
    run zs --list --only=local
    [ "$status" -eq 0 ]
    [[ "$output" == *"s:agent.1"* ]]
    [[ "$output" != *"(ended)"* ]]
}

@test "duplicate names get a warning marker" {
    fixture_row twin 11 0 100 /tmp
    fixture_row twin 12 0 200 /tmp
    run zs --list --only=local
    [[ "$output" == *"duplicate name"* ]]
}

@test "trailing CR in zmx output is tolerated" {
    fixture_row_cr crlf 11 0 100 /tmp
    run zs --list --only=local
    [[ "$output" == *"s:crlf"* ]]
}

@test "search field: rows are TOKEN<tab>NAME<tab>DECOR, NAME is name-only (no client/dir noise)" {
    # regression: fzf searched the display field, so "bld.1" matched the stray
    # "1" (client count / path) in a "bld.2" row. Fix: a dedicated padded name
    # column (searched via --nth on the with-nth-transformed line) with the
    # marker/dir decorations in their own never-searched field.
    fixture_row bld.2 11 2 100 /home/u/workdir1
    run zs --list --only=local
    [ "$status" -eq 0 ]
    row=$(printf '%s\n' "$output" | grep 's:bld\.2')
    [ -n "$row" ]
    [ "$(cut -f1 <<<"$row")" = "s:bld.2" ]                        # field 1: action token
    [ "$(cut -f2 <<<"$row" | sed 's/ *$//')" = "bld.2" ]          # field 2: padded name only
    [[ "$(cut -f2 <<<"$row")" != *"workdir1"* ]]                  # no dir noise in search field
    [[ "$(cut -f2 <<<"$row")" != *"●"* ]]                         # no client marker either
    [[ "$(cut -f3 <<<"$row")" == *"workdir1"* ]]                  # decor carries the dir
}

@test "fzf integration: the picker's exact flag set matches names only (with-nth/nth interplay)" {
    # THE regression this suite previously missed: with --with-nth present, fzf
    # applies --nth to the TRANSFORMED line — a stale index silently matches
    # NOTHING for every query (live-caught 2026-08-03: typing mac14 gave 0/12
    # with @mac14 visibly listed). This test pipes real rows through a REAL fzf
    # with the SAME search-relevant flags as pick(); keep them in sync.
    real_fzf=""
    for p in "$HOME/.local/bin/fzf" /usr/local/bin/fzf /usr/bin/fzf; do
        [ -x "$p" ] && real_fzf="$p" && break
    done
    [ -n "$real_fzf" ] || skip "no real fzf available"
    fixture_row bld.2 11 2 100 /home/u/workdir1
    fixture_row other 12 0 200 /tmp
    rows=$(zs --list --only=local)
    flags=(--ansi --delimiter=$'\t' --with-nth=2,3 --nth=1)
    # a visible row's name MUST match
    [ -n "$(printf '%s\n' "$rows" | "$real_fzf" --filter='bld.2' "${flags[@]}")" ]
    # decoration-only text (dir) must NOT match
    [ -z "$(printf '%s\n' "$rows" | "$real_fzf" --filter='workdir1' "${flags[@]}")" ]
}

@test "version marker: local session on an old daemon (get fails) is flagged, 0.7.0 is not" {
    fixture_row newsess 11 0 100 /tmp
    fixture_row oldsess 12 0 200 /tmp
    ZMX_FAKE_OLD="oldsess" run zs --list --only=local
    [ "$status" -eq 0 ]
    [[ "$(printf '%s\n' "$output" | grep 's:oldsess')" == *"0.6"* ]]
    [[ "$(printf '%s\n' "$output" | grep 's:newsess')" != *"0.6"* ]]
}

@test "zs --stale lists only local sessions whose daemon is old (0.6.0)" {
    fixture_row newsess 11 0 100 /tmp
    fixture_row oldsess 12 0 200 /tmp
    ZMX_FAKE_OLD="oldsess" run zs --stale
    [ "$status" -eq 0 ]
    [[ "$output" == *"oldsess"* ]]
    [[ "$output" != *"newsess"* ]]
}

@test "preview shows a session's 0.7.0 labels above the scrollback" {
    fixture_row foo 11 0 100 /tmp
    ZMX_FAKE_LABELS="project=demo role=claude" run zs --preview s:foo
    [ "$status" -eq 0 ]
    [[ "$output" == *"project=demo"* ]]
    [[ "$output" == *"role=claude"* ]]
    [[ "$output" == *"fake scrollback"* ]]   # scrollback still rendered below
}

@test "zs --label: NAME prints labels, NAME k=v sets them (passthrough to zmx)" {
    ZMX_FAKE_LABELS="role=claude" run zs --label foo
    [ "$status" -eq 0 ]
    [[ "$output" == *"role=claude"* ]]
    run zs --label foo project=demo env=dev
    [ "$status" -eq 0 ]
    grep -q "zmx set foo project=demo env=dev" "$ZMX_FAKE_LOG"
}

@test "host rows appear from ssh config, sessions first" {
    fixture_row local.1 11 0 100 /tmp
    printf 'Host lab9\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    run zs --list
    [[ "$output" == *"h:lab9"* ]]
    s=$(grep -n "s:local.1" <<<"$output" | cut -d: -f1)
    h=$(grep -n "h:lab9" <<<"$output" | cut -d: -f1)
    [ "$s" -lt "$h" ]
}

@test "hosts dedupe by resolved endpoint keeps first-listed alias" {
    printf 'Host short long-alias\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config"
    export SSH_FAKE_G_HOSTNAME=same.endpoint
    run zs --list --only=remote
    [[ "$output" == *"h:short"* ]]
    [[ "$output" != *"h:long-alias"* ]]
}


@test "hosts: Include'd config files contribute host rows (corp WSL layout)" {
    # regression: hosts defined in an Included file were invisible, so a machine
    # whose whole fleet lives in ~/.ssh/config.base showed ZERO hosts to drill.
    printf 'Include config.base\n' > "$HOME/.ssh/config"
    printf 'Host viaInclude\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config.base"
    run zs --list --only=remote
    [[ "$output" == *"h:viaInclude"* ]]
}

@test "hosts: a relative Include resolves against ~/.ssh, and direct hosts still work" {
    printf 'Host direct\n  HostName 9.9.9.9\nInclude config.base\n' > "$HOME/.ssh/config"
    printf 'Host included\n  HostName 1.2.3.4\n' > "$HOME/.ssh/config.base"
    run zs --list --only=remote
    [[ "$output" == *"h:direct"* ]]
    [[ "$output" == *"h:included"* ]]
}

@test "hosts: a missing Include target is harmless" {
    printf 'Include nosuchfile\nHost solo\n  HostName 1.1.1.1\n' > "$HOME/.ssh/config"
    run zs --list --only=remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"h:solo"* ]]
}


@test "hosts: a CRLF ssh config still yields hosts (WSL/Windows-written files)" {
    # A Windows-written ~/.ssh/config ends every line \r\n.
    # Without stripping it the Include target became "config.base\r" (no such
    # file) and host names became "ws15\r" — the picker showed ZERO hosts and
    # said nothing. zs already strips \r from zmx output; ssh config needs it too.
    printf 'Include config.base\r\nHost direct\r\n  HostName 9.9.9.9\r\n' > "$HOME/.ssh/config"
    printf 'Host crlfhost\r\n  HostName 1.2.3.4\r\n' > "$HOME/.ssh/config.base"
    run zs --list --only=remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"h:crlfhost"* ]]   # via the CRLF Include
    [[ "$output" == *"h:direct"* ]]     # and the CRLF direct host
    [[ "$output" != *$'\r'* ]]          # no CR leaks into the rows
}
