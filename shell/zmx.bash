# ~/.bash/.zmx — zmx session integration (all machines).
# Sourced from ~/.bashrc only when zmx is installed. The per-host prompt tag is
# handled by starship (env_var.ZMX_SESSION), NOT here.
command -v zmx >/dev/null 2>&1 || return 0

# ── shell completions ──
eval "$(zmx completions bash)"

# ── auto-attach on interactive SSH ──────────────────────────────────────────
# Every interactive SSH into this box lands in a persistent zmx session, so the
# shell survives disconnects and can be resumed from anywhere (e.g. from
# another machine later). Non-interactive ssh (scp, `ssh host cmd`) never reaches
# here — ~/.bashrc returns early for non-interactive shells — so scripting and
# orchestration stay plain. Opt out for one connection with ZMX_NO_AUTO=1.
# Attach + reap: `exit` inside ends the session but zmx keeps the corpse
# (ended=/exit_code= fields) and its name stays poisoned — kill it.
# Detaching keeps the session for resume.
# Switch hop (spec 003): `zs --hop` inside the session writes its selection to
# ${XDG_RUNTIME_DIR:-/tmp}/zs-hop.<session> and detaches; this loop consumes
# the handoff (read + unlink, exactly once) and attaches the target instead of
# returning — the client MOVES between sessions, attach depth stays 1, and the
# origin keeps running detached. No handoff = the pre-003 single attach.
__zmx_attach_reap() {
    local s="$1" hopf tok
    while :; do
        zmx attach "$s"
        hopf="${XDG_RUNTIME_DIR:-/tmp}/zs-hop.$s"
        [ -f "$hopf" ] || break
        tok=$(head -1 "$hopf" 2>/dev/null); rm -f "$hopf"
        case "$tok" in
        s:*) s="${tok#s:}" ;;                 # existing session → re-attach
        q:*) s="${tok#q:}" ;;                 # free-form name → create+attach
        h:*) ssh "${tok#h:}"; break ;;        # host target → plain connect
        *)   break ;;                         # empty/unknown → stop hopping
        esac
        [ -n "$s" ] || break
    done
    if zmx list 2>/dev/null | awk -F'\t' -v s="$s" '
        { n = $1; sub(/.*name=/, "", n)
          if (n == s) for (i = 1; i <= NF; i++) if ($i ~ /^ended=/) { found = 1; exit } }
        END { exit !found }'; then
        zmx kill "$s" >/dev/null 2>&1
    fi
}

__zmx_ssh_attach() {
    local base target
    # One convention on every host: cwd-based naming (SSH lands in $HOME →
    # home.1, home.2, ...), so an SSH login can resume the very session a
    # closed local tab left detached. Name-explicit ssh aliases
    # (<host>.<session>) bypass this entirely. Pre-existing main/main-N
    # sessions are not resumed automatically; attach them by name once.
    base="${PWD##*/}"
    [ "$PWD" = "$HOME" ] && base=home
    base="${base//[^A-Za-z0-9._-]/-}"
    [ -n "$base" ] || base=shell
    # prefer the newest detached, non-ended base.N session (resume);
    # zmx list prefixes lines with "  " or "→ ", so match name= inside
    # the first field, never anchored at line start.
    target=$(zmx list 2>/dev/null | awk -F'\t' -v b="$base" '
        {
            name = $1; sub(/.*name=/, "", name)
            if (name !~ ("^" b "\\.[0-9]+$")) next
            free = 0; ended = 0; created = 0
            for (i = 1; i <= NF; i++) {
                if ($i == "clients=0")   free = 1
                if ($i ~ /^ended=/)      ended = 1
                if ($i ~ /^created=/) { created = $i; sub(/^created=/, "", created) }
            }
            if (free && !ended && created + 0 > best) { best = created + 0; pick = name }
        }
        END { if (pick) print pick }')
    [ -n "$target" ] || target=$(zn -n "$base")
    __zmx_attach_reap "$target"
    exit
}
if [ -n "$SSH_CONNECTION" ] && [ -z "$ZMX_SESSION" ] && [ -z "$ZMX_NO_AUTO" ]; then
    __zmx_ssh_attach
fi

# (No shell keybinding for the picker: interactive shells here are always
# inside a session, where a picker can't run — and Ctrl-G tends to clash
# with other tools' bindings. Use kitty's ctrl+a>ctrl+f (runs the `zs` fzf picker in a new
# tab, outside the session env), or run `zs` from a rare bare shell.)

# ── terminal tab title + cwd reporting ──────────────────────────────────────
# Inside a session, at every prompt:
#  - OSC 2: name the terminal tab after the session, so the kitty tab bar
#    reads 1:proj.1 2:notes.1. kitty.conf uses `shell_integration
#    no-title` so kitty's own cwd-based titles don't fight this. Over SSH
#    the escape reaches the connecting terminal.
#  - OSC 7: report the real cwd, so kitty's --cwd=current (splits, ctrl+a>c)
#    follows your `cd`s — kitty's own integration can't see inside zmx.
#    Naming is unaffected: panes inherit their base from the sibling session
#    (see zp), never from the cwd, when inside kitty.
if [ -n "$ZMX_SESSION" ]; then
    # The title carries @host (dev@myhost) only while someone is VIEWING the
    # session over SSH, so the connecting terminal's tab shows where you are
    # even mid-TUI. Checked per prompt against the live attach clients, NOT
    # against this shell's own SSH_CONNECTION: that env is baked in at session
    # creation, so a session born from an SSH login would wear @host forever —
    # even attached locally later. A `zmx attach NAME` process with a real
    # terminal on fd0 is a live viewer (the session's holder process parks
    # fd0 on /dev/null once its creator detaches); SSH_CONNECTION in the
    # viewer's env marks it remote. No /proc (macOS): fall back to the old
    # creation-env heuristic — sessions there are viewed locally anyway.
    __zmx_host=$(hostname -s)
    __zmx_re=$(printf '%s' "$ZMX_SESSION" | sed 's/[][^$.*\\]/\\&/g')
    __zmx_remote_viewer() {
        local p tty
        if [ -r /proc/self/environ ]; then
            for p in $(pgrep -f "zmx (a|attach) ${__zmx_re}\$" 2>/dev/null); do
                tty=$(readlink "/proc/$p/fd/0" 2>/dev/null)
                case "$tty" in /dev/pts/*|/dev/tty*) ;; *) continue ;; esac
                grep -qz '^SSH_CONNECTION=' "/proc/$p/environ" 2>/dev/null && return 0
            done
            return 1
        fi
        [ -n "${SSH_CONNECTION:-}" ]
    }
    __zmx_prompt() {
        local t="$ZMX_SESSION"
        __zmx_remote_viewer && t="$ZMX_SESSION@$__zmx_host"
        printf '\033]2;%s\007' "$t"
        printf '\033]7;file://%s%s\033\\' "${HOSTNAME:-$(hostname)}" "$PWD"
    }
    PROMPT_COMMAND="__zmx_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
else
    # Plain (non-session) interactive shells: title by directory so tabs
    # don't stay stuck on the launcher's name (zmx-login / shell).
    __zmx_prompt() {
        local d="${PWD##*/}"; [ "$PWD" = "$HOME" ] && d="~"
        printf '\033]2;%s (shell)\007' "$d"
        printf '\033]7;file://%s%s\033\\' "${HOSTNAME:-$(hostname)}" "$PWD"
    }
    PROMPT_COMMAND="__zmx_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi

# ── session lifecycle helpers ────────────────────────────────────────────────
# zkill: destroy the session you're inside (closing the tab merely detaches).
alias zkill='zmx kill "$ZMX_SESSION"'

# zclean [PREFIX]: with no argument, reap ended corpses only (detached
# sessions are legitimate resumables). With PREFIX, also kill detached
# sessions named PREFIX*. Lists victims and asks first.
zclean() {
    local pfx="${1:-}" victims a
    victims=$(zmx list 2>/dev/null | awk -F'\t' -v p="$pfx" '{
        name = $1; sub(/.*name=/, "", name)
        free = 0; ended = 0
        for (i = 1; i <= NF; i++) {
            if ($i == "clients=0") free = 1
            if ($i ~ /^ended=/)    ended = 1
        }
        if (p == "") { if (ended) print name }
        else if ((free || ended) && index(name, p) == 1) print name
    }')
    [ -n "$victims" ] || { echo "zclean: nothing to clean${pfx:+ for ${pfx}*}"; return 0; }
    printf '%s\n' "$victims"
    read -rp "kill these? [y/N] " a
    [ "$a" = y ] && printf '%s\n' "$victims" | while IFS= read -r s; do zmx kill "$s"; done
}
