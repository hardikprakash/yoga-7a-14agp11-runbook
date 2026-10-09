#!/usr/bin/env bash
# Safety guard for the runbook test suite.
#
# Source this first. It:
#   1. refuses to run as root (a test suite must never touch a real system)
#   2. provides a sandboxed temp HOME with cleanup on exit
#   3. puts PATH stubs in front of mutating commands. Stubs are executable
#      files on PATH, so they also protect *child* processes — ./setup.sh
#      and the module scripts run in their own shells. Read-only subcommands
#      (systemctl is-active, rfkill list, ...) forward to the real binary so
#      that check.sh probes still behave realistically.
#   4. provides assert helpers with a running pass/fail count
#
# Any invocation of a *mutating* subcommand is a test failure unless the
# test calls allow_mutations first (only appropriate when exercising an
# intentionally-mutating path inside the sandbox).

set -uo pipefail

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "FATAL: tests must not run as root" >&2
    exit 1
fi

TEST_TMP="$(mktemp -d /tmp/opencode/runbook-tests.XXXXXX)"
MUTATION_LOG="$TEST_TMP/mutations.log"
STUB_BIN="$TEST_TMP/bin"
: > "$MUTATION_LOG"
mkdir -p "$STUB_BIN"

_failures=0
_tests=0

cleanup_guard() {
    rm -rf "$TEST_TMP"
}
trap cleanup_guard EXIT

_log_mutation() {
    printf '%s\n' "$*" >> "$MUTATION_LOG"
}

# ---------------------------------------------------------- mutation stubs --
_make_stubs() {
    # --- always-mutating: any invocation is a red flag in tests -------------
    local cmd
    for cmd in sudo dnf apt-get pacman zypper modprobe mkinitcpio dracut \
               grub-mkconfig fprintd-enroll; do
        cat > "$STUB_BIN/$cmd" <<STUB
#!/bin/bash
printf '%s %s\n' "$cmd" "\$*" >> "$MUTATION_LOG"
exit 0
STUB
        chmod +x "$STUB_BIN/$cmd"
    done

    # --- systemctl: log+skip mutating verbs, forward read-only verbs --------
    cat > "$STUB_BIN/systemctl" <<STUB
#!/bin/bash
case "\${1:-}" in
    start|stop|restart|enable|disable|mask|unmask|daemon-reload|isolate|edit|preset|link|set-property)
        printf 'systemctl %s\n' "\$*" >> "$MUTATION_LOG"
        exit 0
        ;;
    *)
        exec /usr/bin/systemctl "\$@"
        ;;
esac
STUB
    chmod +x "$STUB_BIN/systemctl"

    # --- rfkill: block/unblock mutate, 'list' is a read-only probe ----------
    cat > "$STUB_BIN/rfkill" <<STUB
#!/bin/bash
case "\${1:-}" in
    block|unblock)
        printf 'rfkill %s\n' "\$*" >> "$MUTATION_LOG"
        exit 0
        ;;
    *)
        exec /usr/sbin/rfkill "\$@" 2>/dev/null || exec /usr/bin/rfkill "\$@" 2>/dev/null || exit 0
        ;;
esac
STUB
    chmod +x "$STUB_BIN/rfkill"

    # --- nmcli: 'radio' toggles the radio; everything else forwards --------
    cat > "$STUB_BIN/nmcli" <<STUB
#!/bin/bash
case "\${1:-}" in
    radio|device|connection|networking)
        # 'nmcli radio' with no args / 'nmcli device status' are queries too,
        # but our scripts only ever use these verbs to change state.
        printf 'nmcli %s\n' "\$*" >> "$MUTATION_LOG"
        exit 0
        ;;
    *)
        exec /usr/bin/nmcli "\$@" 2>/dev/null || exit 0
        ;;
esac
STUB
    chmod +x "$STUB_BIN/nmcli"

    # --- tee: log + discard. (Scripts use 'sudo tee', covered by sudo stub;
    #     a stray plain tee must not create files outside the sandbox.) -----
    cat > "$STUB_BIN/tee" <<STUB
#!/bin/bash
printf 'tee %s\n' "\$*" >> "$MUTATION_LOG"
cat > /dev/null
exit 0
STUB
    chmod +x "$STUB_BIN/tee"

    # --- git: mutating subcommands logged, read-only forwarded -------------
    cat > "$STUB_BIN/git" <<STUB
#!/bin/bash
case "\${1:-}" in
    clone|push|pull|submodule|remote|commit|reset|checkout|clean|revert|cherry-pick)
        printf 'git %s\n' "\$*" >> "$MUTATION_LOG"
        exit 0
        ;;
    *)
        exec /usr/bin/git "\$@"
        ;;
esac
STUB
    chmod +x "$STUB_BIN/git"

    # --- flatpak: installs logged, queries forwarded -----------------------
    cat > "$STUB_BIN/flatpak" <<STUB
#!/bin/bash
case "\${1:-}" in
    install|uninstall|update)
        printf 'flatpak %s\n' "\$*" >> "$MUTATION_LOG"
        exit 0
        ;;
    *)
        exec /usr/bin/flatpak "\$@" 2>/dev/null || exit 1
        ;;
esac
STUB
    chmod +x "$STUB_BIN/flatpak"
}

export MUTATION_LOG
_make_stubs
PATH="$STUB_BIN:$PATH"
export PATH

# ------------------------------------------------------------- sandboxes ----
# sandbox_home — empty HOME; sets and exports HOME/BASHRC.
sandbox_home() {
    SANDBOX="$TEST_TMP/home-$RANDOM$RANDOM"
    mkdir -p "$SANDBOX"
    HOME="$SANDBOX"
    BASHRC="$SANDBOX/.bashrc"
    export HOME BASHRC
}

# ----------------------------------------------------------- mutation API ---
# Reset the log before a section that intentionally mutates the sandbox.
allow_mutations() { : > "$MUTATION_LOG"; }

assert_no_mutations() {
    local context="${1:-}"
    if [ -s "$MUTATION_LOG" ]; then
        _fail "$context: mutating commands were invoked:"$'\n'"$(sed 's/^/         /' "$MUTATION_LOG")"
        : > "$MUTATION_LOG"
    else
        _pass "$context: no mutating commands invoked"
    fi
}

assert_mutations_logged() { # message needle — expect exactly this mutation
    local context="$1" needle="$2"
    if grep -qF -- "$needle" "$MUTATION_LOG"; then
        _pass "$context"
        : > "$MUTATION_LOG"
    else
        _fail "$context (expected '$needle'; log: $(tr '\n' ';' <"$MUTATION_LOG"))"
    fi
}

# ---------------------------------------------------------------- asserts ---
_pass() { _tests=$((_tests + 1)); printf '  ok   %s\n' "$1"; }
_fail() { _tests=$((_tests + 1)); _failures=$((_failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

assert_eq() { # actual expected message
    if [ "$1" = "$2" ]; then _pass "$3"; else _fail "$3 (got: '$1', want: '$2')"; fi
}

assert_contains() { # haystack needle message
    if grep -qF -- "$2" <<<"$1"; then _pass "$3"; else _fail "$3 (no '$2' in output)"; fi
}

assert_not_contains() { # haystack needle message
    if grep -qF -- "$2" <<<"$1"; then _fail "$3 (unexpected '$2')"; else _pass "$3"; fi
}

assert_file_exists() { # path message
    if [ -e "$1" ]; then _pass "$2"; else _fail "$2 (missing: $1)"; fi
}

assert_file_absent() { # path message
    if [ -e "$1" ]; then _fail "$2 (exists: $1)"; else _pass "$2"; fi
}

assert_rc() { # actual_rc expected_rc message
    if [ "$1" -eq "$2" ]; then _pass "$3"; else _fail "$3 (exit $1, want $2)"; fi
}

finish() {
    echo
    if [ "$_failures" -gt 0 ]; then
        printf '%s: %d/%d checks failed\n' "$(basename "$0")" "$_failures" "$_tests" >&2
        exit 1
    fi
    printf '%s: all %d checks passed\n' "$(basename "$0")" "$_tests"
    exit 0
}
