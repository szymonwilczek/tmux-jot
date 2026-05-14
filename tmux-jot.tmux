#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value

    option_value=$(tmux show-option -gqv "$option")
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

shell_quote() {
    printf '%q' "$1"
}

KEY=$(get_tmux_option "@jot-key-bind" "j")
USE_PREFIX=$(get_tmux_option "@jot-use-prefix" "false")
SCRIPT_PATH="$CURRENT_DIR/scripts/jot.sh"
SCRIPT_PATH_Q="$(shell_quote "$SCRIPT_PATH")"
RUN_COMMAND="$SCRIPT_PATH_Q main #{q:client_name} #{q:session_name} > /dev/null 2>&1"

if [ "$USE_PREFIX" == "true" ]; then
    tmux bind-key "$KEY" run-shell "$RUN_COMMAND"
else
    tmux bind-key -n "$KEY" run-shell "$RUN_COMMAND"
fi
