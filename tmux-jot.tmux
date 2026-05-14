#!/usr/bin/env bash

CURRENT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

jot_get_tmux_option() {
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

jot_shell_quote() {
    printf '%q' "$1"
}

KEY=$(jot_get_tmux_option "@jot-key-bind" "j")
USE_PREFIX=$(jot_get_tmux_option "@jot-use-prefix" "false")
SCRIPT_PATH="$CURRENT_DIR/scripts/jot.sh"
SCRIPT_PATH_Q="$(jot_shell_quote "$SCRIPT_PATH")"

jot_bind_key() {
    local key="$1"
    local use_prefix="$2"
    local mode="$3"
    local repeat="${4:-false}"
    local command
    local bind_args=(bind-key)

    case "$key" in
    "" | off | none | disabled) return 0 ;;
    esac

    if [ "$repeat" == "true" ]; then
        bind_args+=(-r)
    fi

    command="$SCRIPT_PATH_Q $mode #{q:client_name} #{q:session_name} > /dev/null 2>&1"
    if [ "$use_prefix" == "true" ]; then
        tmux "${bind_args[@]}" "$key" run-shell "$command"
    else
        bind_args+=(-n)
        tmux "${bind_args[@]}" "$key" run-shell "$command"
    fi
}

jot_bind_resize_key() {
    local key="$1"
    local use_prefix="$2"
    local repeat_key="$3"
    local mode="$4"

    case "$key" in
    "" | off | none | disabled) return 0 ;;
    esac

    jot_bind_key "$key" "$use_prefix" "$mode" "true"
    jot_bind_key "$repeat_key" "true" "$mode" "true"
}

SWITCH_KEY=$(jot_get_tmux_option "@jot-switch-key-bind" "")
SWITCH_USE_PREFIX=$(jot_get_tmux_option "@jot-switch-use-prefix" "false")
CONTENT_SEARCH_KEY=$(jot_get_tmux_option "@jot-content-search-key-bind" "M-w")
CONTENT_SEARCH_USE_PREFIX=$(jot_get_tmux_option "@jot-content-search-use-prefix" "true")
DOCTOR_KEY=$(jot_get_tmux_option "@jot-doctor-key-bind" "M-i")
DOCTOR_USE_PREFIX=$(jot_get_tmux_option "@jot-doctor-use-prefix" "true")
CLEANUP_KEY=$(jot_get_tmux_option "@jot-cleanup-key-bind" "M-k")
CLEANUP_USE_PREFIX=$(jot_get_tmux_option "@jot-cleanup-use-prefix" "true")
# "=" instead of "+" so increasing does not require Shift in the resize sequence
# TODO: this should be still done with PLUS (or something else i come up with, it does not work smoothly as i want to)
RESIZE_INCREASE_KEY=$(jot_get_tmux_option "@jot-resize-increase-key-bind" "M-=")
RESIZE_INCREASE_USE_PREFIX=$(jot_get_tmux_option "@jot-resize-increase-use-prefix" "true")
RESIZE_INCREASE_REPEAT_KEY=$(jot_get_tmux_option "@jot-resize-increase-repeat-key-bind" "=")
RESIZE_DECREASE_KEY=$(jot_get_tmux_option "@jot-resize-decrease-key-bind" "M--")
RESIZE_DECREASE_USE_PREFIX=$(jot_get_tmux_option "@jot-resize-decrease-use-prefix" "true")
RESIZE_DECREASE_REPEAT_KEY=$(jot_get_tmux_option "@jot-resize-decrease-repeat-key-bind" "-")
RESIZE_RESET_KEY=$(jot_get_tmux_option "@jot-resize-reset-key-bind" "M-r")
RESIZE_RESET_USE_PREFIX=$(jot_get_tmux_option "@jot-resize-reset-use-prefix" "true")

jot_bind_key "$KEY" "$USE_PREFIX" "main"
jot_bind_key "$SWITCH_KEY" "$SWITCH_USE_PREFIX" "switch"
jot_bind_key "$CONTENT_SEARCH_KEY" "$CONTENT_SEARCH_USE_PREFIX" "content_search"
jot_bind_key "$DOCTOR_KEY" "$DOCTOR_USE_PREFIX" "doctor"
jot_bind_key "$CLEANUP_KEY" "$CLEANUP_USE_PREFIX" "cleanup"
jot_bind_resize_key "$RESIZE_INCREASE_KEY" "$RESIZE_INCREASE_USE_PREFIX" "$RESIZE_INCREASE_REPEAT_KEY" "resize_increase"
jot_bind_resize_key "$RESIZE_DECREASE_KEY" "$RESIZE_DECREASE_USE_PREFIX" "$RESIZE_DECREASE_REPEAT_KEY" "resize_decrease"
jot_bind_key "$RESIZE_RESET_KEY" "$RESIZE_RESET_USE_PREFIX" "resize_reset"
