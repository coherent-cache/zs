# tests/helpers.bash — shared setup for the zs bats suite.
#
# Strategy: the scripts under test prepend $HOME/.local/bin (and
# /opt/homebrew/bin) to PATH, so shims must live in a FAKE $HOME's
# .local/bin to win the race against real zmx/kitten/ssh installs.
# Everything below runs against fakes — no kitty, no zmx daemon, no network.
#
# EVERY test file MUST run setup_shims (via `setup() { setup_shims; }`) — it
# redirects $HOME to a throwaway dir. WITHOUT it, fixtures that write
# `$HOME/.ssh/config` clobber the developer's REAL ssh config.

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup_shims() {
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME/.local/bin" "$HOME/.ssh" "$HOME/.cache"

    local f
    for f in zmx kitten ssh; do
        ln -sf "$ROOT/tests/fakes/$f" "$HOME/.local/bin/$f"
    done
    for f in zs zn zp zmx-login; do
        ln -sf "$ROOT/bin/$f" "$HOME/.local/bin/$f"
    done
    export PATH="$HOME/.local/bin:$PATH"

    export ZMX_FAKE_LIST="$BATS_TEST_TMPDIR/zmx.list"
    export ZMX_FAKE_LOG="$BATS_TEST_TMPDIR/zmx.log"
    export SSH_FAKE_LOG="$BATS_TEST_TMPDIR/ssh.log"
    export KITTEN_FAKE_LS=""
    export SSH_FAKE_STDOUT="" SSH_FAKE_RC=0
    : > "$ZMX_FAKE_LIST"; : > "$ZMX_FAKE_LOG"; : > "$SSH_FAKE_LOG"

    # scripts under test must not see the developer's kitty/session env
    unset ZMX_SESSION ZMX_NO_AUTO KITTY_WINDOW_ID KITTY_PID KITTY_LISTEN_ON
}

# fixture_row NAME PID CLIENTS CREATED DIR [extra-tab-fields…] — one real-format
# zmx list line ("  " gutter). fixture_row_arrow uses the "→ " gutter variant.
fixture_row() {
    local name="$1" pid="$2" clients="$3" created="$4" dir="$5"; shift 5
    local line="  name=${name}	pid=${pid}	clients=${clients}	created=${created}	start_dir=${dir}"
    local x; for x in "$@"; do line="${line}	${x}"; done
    printf '%s\n' "$line" >> "$ZMX_FAKE_LIST"
}
fixture_row_arrow() {
    local name="$1" pid="$2" clients="$3" created="$4" dir="$5"; shift 5
    local line="→ name=${name}	pid=${pid}	clients=${clients}	created=${created}	start_dir=${dir}"
    local x; for x in "$@"; do line="${line}	${x}"; done
    printf '%s\n' "$line" >> "$ZMX_FAKE_LIST"
}

# fixture_row_cr — like fixture_row but with a trailing CR (zmx output can
# carry one; parsers must tolerate it).
fixture_row_cr() {
    local name="$1" pid="$2" clients="$3" created="$4" dir="$5"; shift 5
    printf '  name=%s	pid=%s	clients=%s	created=%s	start_dir=%s\r\n' \
        "$name" "$pid" "$clients" "$created" "$dir" >> "$ZMX_FAKE_LIST"
}

assert_log_has()   { grep -qF -- "$1" "$2" || { echo "expected '$1' in $(basename "$2"):"; cat "$2"; return 1; }; }
assert_log_lacks() { ! grep -qF -- "$1" "$2" || { echo "did NOT expect '$1' in $(basename "$2"):"; cat "$2"; return 1; }; }
