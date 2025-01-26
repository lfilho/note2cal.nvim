#!/bin/bash

# Get the directory of the script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$DIR/.."

# Add plugin's lua directory to LUA_PATH
# Include both the current directory and the system's default paths
export LUA_PATH="${PLUGIN_DIR}/lua/?.lua;${PLUGIN_DIR}/lua/?/init.lua;$(lua -e 'print(package.path)')"

# Run the tests
busted "${PLUGIN_DIR}/spec"

# Get the exit code
exit_code=$?

# If tests failed, exit with the error code
if [ $exit_code -ne 0 ]; then
    exit $exit_code
fi
