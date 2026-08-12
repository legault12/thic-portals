#!/usr/bin/env sh
#
# Syntax-check the addon and run every test suite.
#
#   ./tests/run.sh
#   LUA=lua5.4 ./tests/run.sh
#   LUAC=none ./tests/run.sh    # force the loadfile syntax check
#
# Runs from any directory. Exits non-zero on the first failure so CI and a local
# pre-push check behave the same way.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
addon_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)

cd "$addon_dir"

# Interpreter: honour $LUA, otherwise take the first one available. Distributions
# disagree about whether the binary is lua, lua5.4 or lua5.3.
if [ -z "${LUA:-}" ]; then
    for candidate in lua lua5.4 lua5.3 lua5.5; do
        if command -v "$candidate" >/dev/null 2>&1; then
            LUA=$candidate
            break
        fi
    done
fi

if [ -z "${LUA:-}" ]; then
    echo "error: no lua interpreter found (tried lua, lua5.4, lua5.3, lua5.5)" >&2
    echo "       install one, or set LUA=/path/to/lua" >&2
    exit 1
fi

# luac is preferred for the syntax pass, but loadfile through the interpreter is
# equivalent and always available, so a missing luac is not a reason to skip it.
# LUAC=none forces that path, which is the only way to exercise it on a system
# where luac sits next to lua.
if [ "${LUAC:-}" = "none" ]; then
    LUAC=""
elif [ -z "${LUAC:-}" ]; then
    for candidate in luac luac5.4 luac5.3 luac5.5; do
        if command -v "$candidate" >/dev/null 2>&1; then
            LUAC=$candidate
            break
        fi
    done
fi

# The addon's own files. Libs/ is third-party and targets the WoW 5.1 runtime, so
# it is deliberately not checked here.
ADDON_FILES="Config.lua Events.lua InviteTrade.lua ThicPortals.lua UI.lua Utils.lua"

echo "lua:  $($LUA -v 2>&1 | head -1)"
if [ -n "${LUAC:-}" ]; then
    echo "luac: $LUAC"
else
    echo "luac: not found, using $LUA loadfile instead"
fi
echo

echo "== syntax =="
for file in $ADDON_FILES tests/*.lua; do
    if [ -n "${LUAC:-}" ]; then
        "$LUAC" -p "$file"
    else
        "$LUA" -e "assert(loadfile('$file'))"
    fi
    echo "  ok  $file"
done

echo
echo "== suites =="
for suite in tests/test_*.lua; do
    # Captured explicitly rather than interpolated into printf: a command
    # substitution used as an argument throws away the suite's exit status, so a
    # failing suite would have reported green.
    if suite_output=$("$LUA" "$suite" 2>&1); then
        printf '  %s\n' "$suite_output"
    else
        printf '  FAILED %s\n' "$suite" >&2
        printf '%s\n' "$suite_output" >&2
        exit 1
    fi
done

echo
echo "all checks passed"
