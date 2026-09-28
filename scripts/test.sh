#!/bin/bash

# Get the directory of the script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$DIR/.."

# Pin to Lua 5.1 explicitly (matches the Lua 5.1/LuaJIT semantics Neovim actually
# runs plugin code under) instead of trusting whatever bare `lua`/`busted` resolve
# to on PATH. Homebrew's unversioned `lua` formula rolls forward in place (it moved
# 5.4 -> 5.5 already), which silently strands any busted/luarocks rocks that were
# built against the previous ABI. `lua@5.1` is a separately versioned keg that isn't
# affected by that, so we target it directly.
LUA_BIN="$(brew --prefix lua@5.1 2>/dev/null)/bin/lua5.1"
if [ ! -x "$LUA_BIN" ]; then
    echo "error: lua@5.1 not found. Install it with: brew install lua@5.1" >&2
    exit 1
fi

BUSTED_BIN="$(luarocks --lua-version=5.1 path --lr-bin 2>/dev/null)/busted"
if [ ! -x "$BUSTED_BIN" ]; then
    echo "error: busted not found for Lua 5.1. Install it with: luarocks --lua-version=5.1 install busted" >&2
    exit 1
fi

# Add plugin's lua directory to LUA_PATH
# Include both the current directory and the system's default paths
export LUA_PATH="${PLUGIN_DIR}/lua/?.lua;${PLUGIN_DIR}/lua/?/init.lua;$("$LUA_BIN" -e 'print(package.path)')"

# Run the tests
"$BUSTED_BIN" "${PLUGIN_DIR}/spec"

# Get the exit code
exit_code=$?

# If tests failed, exit with the error code
if [ $exit_code -ne 0 ]; then
    exit $exit_code
fi
