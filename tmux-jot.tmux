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

bind_jot_key() {
    local key="$1"
    local use_prefix="$2"
    local mode="$3"
    local command

    case "$key" in
    "" | off | none | disabled) return 0 ;;
    esac

    command="$SCRIPT_PATH_Q $mode #{q:client_name} #{q:session_name} > /dev/null 2>&1"
    if [ "$use_prefix" == "true" ]; then
        tmux bind-key "$key" run-shell "$command"
    else
        tmux bind-key -n "$key" run-shell "$command"
    fi
}

SWITCH_KEY=$(get_tmux_option "@jot-switch-key-bind" "")
SWITCH_USE_PREFIX=$(get_tmux_option "@jot-switch-use-prefix" "false")
CONTENT_SEARCH_KEY=$(get_tmux_option "@jot-content-search-key-bind" "M-w")
CONTENT_SEARCH_USE_PREFIX=$(get_tmux_option "@jot-content-search-use-prefix" "true")
DOCTOR_KEY=$(get_tmux_option "@jot-doctor-key-bind" "M-i")
DOCTOR_USE_PREFIX=$(get_tmux_option "@jot-doctor-use-prefix" "true")

bind_jot_key "$KEY" "$USE_PREFIX" "main"
bind_jot_key "$SWITCH_KEY" "$SWITCH_USE_PREFIX" "switch"
bind_jot_key "$CONTENT_SEARCH_KEY" "$CONTENT_SEARCH_USE_PREFIX" "content_search"
bind_jot_key "$DOCTOR_KEY" "$DOCTOR_USE_PREFIX" "doctor"
