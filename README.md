# zs — session + host picker for zmx

One launcher for any work context, local or remote: an fzf picker over
[zmx](https://zmx.sh) sessions and ssh hosts, with kitty integration where
available and graceful degradation everywhere else (SSH logins, bare
consoles, macOS + Linux).

The picker is the shell entry for new terminal tabs; split panes bypass it
and join the tab's project. Sessions are named, purposeful things — close a
tab and the session survives; pick it again from anywhere, including over
SSH.

## Tools

| Tool | Role |
|---|---|
| `bin/zs` | fzf picker over sessions + hosts; attach/create/kill/drill; `zs NAME` attaches a session/host/query directly with no picker; also the headless `zs --attach NAME [cmd…]` used by kitty session files |
| `bin/zn` | auto-numbered sessions on this host (`dev.1`, `dev.2`, …); `-r` runs a command detached and prints the bare name (scriptable) |
| `bin/zp` | split-pane helper: next sibling session for the current tab's project; in ssh-wrapper tabs, another connection to that host |
| `bin/zmx-login` | terminal shell entry: picker with plain-login-shell fallback |
| `shell/zmx.bash` | bashrc integration: SSH auto-attach, tab titles (OSC 2) + cwd reporting (OSC 7), `zkill`/`zclean`. Titles show `name@host` only while a live SSH viewer is attached (checked per prompt against the session's attach clients on Linux; a session merely *born* over SSH stays plain when viewed locally) |

## Name grammar

- `project.N` — local sessions, numbered at birth (names are birth-only;
  zmx has no rename).
- `@host.N` — an **outbound ssh connection FROM this machine** to `host`.
  The `@` marks remote-ness everywhere the name shows (picker, tab title).
  The session's process IS `ssh host` — no local shell runs inside, and no
  `@` name can ever be born as a local shell.
- `@host.sess` — pinned to remote session `sess` (rides ssh dispatcher
  aliases: `ssh host.sess` remote-attaches `sess`).
- `@host.sess.N` — sibling of a pinned session, created by splits; the
  local name always matches the remote session name.

Host aliases must be dot-free — the first dot separates host from session.

## Picker keys

Rows are grouped by **locality**: local sessions, then remote `@host.*`
wrappers, then connectable hosts, then ended corpses. A host's place in the
host band follows the recency of ANY session on it — an active `@ws105.bld`
floats ws105 to the top even with no recent bare connect.

| Key | Action |
|---|---|
| `enter` | go: focus/attach a session; connect/resume a host |
| `ctrl-n` | create a **local** session named exactly as typed (never an `@` wrapper — a local name may collide with a host alias) |
| `tab` | complete: host row → `@host.` (type the session), session row → its name |
| `ctrl-s` | drill the selected host → pick a **remote** zmx session (`@host.sess`); no zmx / unreachable → plain connect |
| `ctrl-x` | kill the highlighted session — or all marked ones |
| `space` | mark rows (optional, for batch kill) |
| `alt-l` / `alt-r` / `alt-a` | view: local / remote (wrappers + hosts) / all |
| `alt-e` | toggle exact matching (`ws15` stops matching `ws105`) |
| `ctrl-←` / `ctrl-→` | word-wise cursor movement |
| `ctrl-/` | toggle preview |
| `esc` | back to the full list (inside a drill) · cancel (top level) |
| `?` | show this full keymap in the preview pane |

The header updates as you type to show what `enter` and `ctrl-n` will do with
the current query — the `@` convention is surfaced, not memorized. A
single-line footer shows the keys, sized to the terminal (more on a wide
window, the essentials on a narrow one; the table above is the full set).
Session previews are ANSI-stripped so TUI scrollback reads as plain text.

## Diagnostics & session control

`zs` never fails silently: an abnormal exit or a degraded row always names its
cause, using the ssh **alias** only (never a resolved address or username).

| Situation | What you see |
|---|---|
| host refused this machine's key | `⚠ auth refused — connect interactively for password` |
| host down / filtered / unresolvable | `⚠ unreachable — connection failed (timeout/refused)` |
| connected, zmx absent there | `⚠ no zmx on <host> — enter connects plainly` |
| reachable, no sessions | `○ no sessions yet — enter connects, ctrl-n creates` |
| query matches nothing | `no match for "x" — no such session, and no ssh host by that name on this machine` |
| target is this machine | refuses the circular connect and says so |

Inside a zmx session, bare **`zs` means switch** (the hop picker) whenever it
has an interactive terminal; `zs --hop` remains explicit. Scripts and background
agents never hop — a stale inherited `$ZMX_SESSION` is not treated as proof of
being in a session.

A machine never offers **itself** as a host row.

### Session labels (zmx 0.7.0)

Sessions created through `zs`/`zp`/`zn` are stamped `creator`, `role`, `cwd`,
shown as dim chips in the row and in the preview. Labels are read from the
`zmx list` output already fetched, so they cost no extra process per render.

```sh
zs --label NAME             # read a session's labels
zs --label NAME role=job    # set (k= removes)
zs --list --only=label:role=claude   # scope the list to a label
zs --stale                  # local sessions still on a pre-0.7.0 daemon
```

Sessions on an older daemon have no labels, are marked `⚠0.6`, and every
feature degrades silently around them. Filtering is client-side — `zmx ls
--where` does not filter in 0.7.0.

### Splits

A split from a pane attached to `@host.…` creates the next wrapper **on that
same host** (the source pane is identified through kitty's per-tab
`active_window_history`, matching either its `zmx attach` or its `ssh` child).
From a local pane, splits keep cwd/theme naming. If the source cannot be
identified, it falls back to local and says so — it never guesses a host.

## Dependencies

| Dependency | Status | Missing → |
|---|---|---|
| zmx (0.6+) | **required** | plain login shell (login paths never error a fresh tab) |
| bash + POSIX userland | **required** | — (BSD and GNU both fine) |
| fzf ≥ 0.59 | fuzzy picker UI only | plain numbered menu (same rows/actions, no fuzzy search); `zs NAME` never needs fzf. Distro fzf is often too old (`--accept-nth` is 0.59, Jan 2025) — install from [fzf releases](https://github.com/junegunn/fzf/releases) |
| OpenSSH ≥ 6.8 | host features only | sessions-only picker |
| kitty | optional | no tab focus/"· tab N"/sibling naming; everything else works in any terminal |
| python3 | optional (with kitty) | kitty JSON features disable silently |

No daemon; all state under `~/.cache/zs/` (reconstructible caches only).
Ended sessions ("corpses") stay listed ✗ for 7 days for post-mortem, then
are reaped at picker start. A detached session is NOT dead — only ended
ones are ever auto-reaped.

## Install

**Via chezmoi:**

```toml
# .chezmoiexternal.toml
[".local/share/zs"]
    type = "git-repo"
    url = "https://github.com/coherent-cache/zs.git"
    refreshPeriod = "168h"
```

with `symlink_*` sources pointing `~/.local/bin/{zs,zn,zp,zmx-login}` into
`~/.local/share/zs/bin/` and the bash config sourcing `shell/zmx.bash`.

**Manual:**

```sh
git clone https://github.com/coherent-cache/zs ~/.local/share/zs
ln -s ~/.local/share/zs/bin/* ~/.local/bin/
echo 'command -v zmx >/dev/null && . ~/.local/share/zs/shell/zmx.bash' >> ~/.bashrc
```

Kitty users: set `shell ~/.local/bin/zmx-login` and
`shell_integration enabled no-title` in kitty.conf, map splits to zp and
new-tab pickers to zs (use absolute paths — kitty resolves `launch` against
its own PATH). Enable socket remote control for tab-focus features.

## Tests

```sh
make test    # bats suite against fake zmx/kitten/ssh shims —
             # no kitty, no zmx daemon, no network needed
```

The suite pins the hard-won parsing rules: the zmx list gutter, corpse
lifecycle, the `@`-name → connection mapping, sibling-split naming, and
view-filter recovery.
