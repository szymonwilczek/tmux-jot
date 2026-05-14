#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value=$(tmux show-option -gqv "$option")
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

KEY=$(get_tmux_option "@jot-key-bind" "j")
USE_PREFIX=$(get_tmux_option "@jot-use-prefix" "false")

if [ "$USE_PREFIX" == "true" ]; then
    tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/jot.sh main > /dev/null 2>&1"
else
    tmux bind-key -n "$KEY" run-shell "$CURRENT_DIR/scripts/jot.sh main > /dev/null 2>&1"
fi
