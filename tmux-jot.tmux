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

SCRIPT_PATH="$CURRENT_DIR/scripts/jot.sh"
SCRIPT_PATH_Q="$(jot_shell_quote "$SCRIPT_PATH")"

jot_bind_mode() {
    local mode="$1"
    local first_spec="${2:-}"
    local command
    local spec
    local bind_args

    case "$first_spec" in
    "" | off | none | disabled) return 0 ;;
    esac

    command="$SCRIPT_PATH_Q $mode #{q:client_name} #{q:session_name} > /dev/null 2>&1"
    shift

    for spec in "$@"; do
        case "$spec" in
        "" | off | none | disabled) continue ;;
        esac

        read -r -a bind_args <<<"$spec"
        tmux bind-key "${bind_args[@]}" run-shell "$command"
    done
}

# bind specs are passed directly to tmux bind-key
# example: "M-w" uses the prefix table, "-n M-j" uses the root table, "-r M-=" is repeatable
MAIN_BIND=$(jot_get_tmux_option "@jot-key-bind" "-n j")
SWITCH_BIND=$(jot_get_tmux_option "@jot-switch-key-bind" "")
CONTENT_SEARCH_BIND=$(jot_get_tmux_option "@jot-content-search-key-bind" "M-w")
DOCTOR_BIND=$(jot_get_tmux_option "@jot-doctor-key-bind" "M-i")
CLEANUP_BIND=$(jot_get_tmux_option "@jot-cleanup-key-bind" "M-k")
# "=" instead of "+" so increasing does not require Shift in the resize sequence
# TODO: this should be still done with PLUS (or something else i come up with, it does not work smoothly as i want to)
RESIZE_INCREASE_BIND=$(jot_get_tmux_option "@jot-resize-increase-key-bind" "-r M-=")
RESIZE_INCREASE_SHIFT_BIND=$(jot_get_tmux_option "@jot-resize-increase-shift-key-bind" "-r M-+")
RESIZE_INCREASE_REPEAT_BIND=$(jot_get_tmux_option "@jot-resize-increase-repeat-key-bind" "-r =")
RESIZE_INCREASE_REPEAT_SHIFT_BIND=$(jot_get_tmux_option "@jot-resize-increase-repeat-shift-key-bind" "-r +")
RESIZE_DECREASE_BIND=$(jot_get_tmux_option "@jot-resize-decrease-key-bind" "-r M--")
RESIZE_DECREASE_SHIFT_BIND=$(jot_get_tmux_option "@jot-resize-decrease-shift-key-bind" "-r M-_")
RESIZE_DECREASE_REPEAT_BIND=$(jot_get_tmux_option "@jot-resize-decrease-repeat-key-bind" "-r -")
RESIZE_DECREASE_REPEAT_SHIFT_BIND=$(jot_get_tmux_option "@jot-resize-decrease-repeat-shift-key-bind" "-r _")
RESIZE_RESET_BIND=$(jot_get_tmux_option "@jot-resize-reset-key-bind" "M-r")

jot_bind_mode "main" "$MAIN_BIND"
jot_bind_mode "switch" "$SWITCH_BIND"
jot_bind_mode "content_search" "$CONTENT_SEARCH_BIND"
jot_bind_mode "doctor" "$DOCTOR_BIND"
jot_bind_mode "cleanup" "$CLEANUP_BIND"
jot_bind_mode "resize_increase" "$RESIZE_INCREASE_BIND" "$RESIZE_INCREASE_SHIFT_BIND" "$RESIZE_INCREASE_REPEAT_BIND" "$RESIZE_INCREASE_REPEAT_SHIFT_BIND"
jot_bind_mode "resize_decrease" "$RESIZE_DECREASE_BIND" "$RESIZE_DECREASE_SHIFT_BIND" "$RESIZE_DECREASE_REPEAT_BIND" "$RESIZE_DECREASE_REPEAT_SHIFT_BIND"
jot_bind_mode "resize_reset" "$RESIZE_RESET_BIND"
