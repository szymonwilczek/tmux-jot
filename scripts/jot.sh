#!/usr/bin/env bash

set -u

MODE="${1:-main}"

tmux_format() {
    tmux display-message -p "$1" 2>/dev/null || true
}

tmux_option() {
    local option="$1"
    local default_value="${2:-}"
    local value

    value="$(tmux show-option -gqv "$option" 2>/dev/null || true)"
    if [ -n "$value" ]; then
        printf '%s' "$value"
    else
        printf '%s' "$default_value"
    fi
}

tmux_target_option() {
    local target="$1"
    local option="$2"
    local default_value="${3:-}"
    local value

    value="$(tmux show-option -t "$target" -qv "$option" 2>/dev/null || true)"
    if [ -n "$value" ]; then
        printf '%s' "$value"
    else
        printf '%s' "$default_value"
    fi
}

is_true() {
    case "${1:-}" in
    1 | on | true | yes | y) return 0 ;;
    *) return 1 ;;
    esac
}

expand_path() {
    case "$1" in
    \~) printf '%s' "$HOME" ;;
    \~/*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    *) printf '%s' "$1" ;;
    esac
}

normalize_extension() {
    local ext="$1"

    ext="${ext#.}"
    ext="${ext//\//_}"
    [ -n "$ext" ] || ext="md"
    printf '%s' "$ext"
}

safe_session_name() {
    local input="$1"
    local safe

    safe="$(printf '%s' "$input" | sed 's/[^A-Za-z0-9_-]/_/g')"
    [ -n "$safe" ] || safe="session"
    printf '%s' "$safe"
}

tmux_title() {
    printf '%s' "$1" | sed 's/#/##/g'
}

render_template() {
    local template="$1"

    template="${template//\{icon\}/$ICON}"
    template="${template//\{session\}/$SESSION_NAME}"
    template="${template//\{note\}/${NOTE_NAME:-$SESSION_NAME}}"
    template="${template//\{file\}/$FILE_PATH}"
    printf '%s' "$template"
}

shell_join() {
    local output=""
    local quoted
    local arg

    for arg in "$@"; do
        printf -v quoted '%q' "$arg"
        output="${output}${output:+ }${quoted}"
    done

    printf '%s' "$output"
}

has_note_file() {
    [ -n "${1:-}" ] && [ -e "$1" ]
}

message_client() {
    local message="$1"

    if [ -n "$SOURCE_CLIENT" ]; then
        tmux display-message -c "$SOURCE_CLIENT" "tmux-jot: $message" 2>/dev/null || true
    else
        tmux display-message "tmux-jot: $message" 2>/dev/null || true
    fi
}

debug_log() {
    local message="$1"

    is_true "$DEBUG" || return 0
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >>"$LOG_FILE" 2>/dev/null || true
}

note_name_is_valid() {
    local name="$1"

    [ -n "$name" ] || return 1
    [[ "$name" != *"/"* ]] || return 1
    [[ "$name" != *$'\n'* ]] || return 1
    [[ "$name" != *$'\r'* ]] || return 1
    return 0
}

list_notes() {
    local file
    local name

    shopt -s nullglob
    for file in "$JOT_DIR"/*."$EXT"; do
        [ -f "$file" ] || continue
        name="${file##*/}"
        printf '%s\n' "${name%."$EXT"}"
    done | sort
    shopt -u nullglob
}

run_fzf() {
    local prompt_quoted
    local script

    printf -v prompt_quoted '%q' "$FZF_PROMPT"
    script="exec $FZF_COMMAND $FZF_OPTIONS --prompt=$prompt_quoted --print-query --expect=enter"

    "$COMMAND_SHELL" -c "$script"
}

editor_command() {
    local file="$1"
    local file_quoted

    printf -v file_quoted '%q' "$file"
    printf 'exec %s %s' "$EDITOR_COMMAND" "$file_quoted"
}

set_hidden_session_options() {
    tmux set-option -t "$POPUP_SESSION" status off 2>/dev/null || true
    tmux set-option -t "$POPUP_SESSION" detach-on-destroy on 2>/dev/null || true
    tmux set-option -t "$POPUP_SESSION" @jot-source-client "$SOURCE_CLIENT" 2>/dev/null || true
    tmux set-option -t "$POPUP_SESSION" @jot-origin-session "$SESSION_NAME" 2>/dev/null || true
}

new_popup_token() {
    local kind="$1"

    printf '%s:%s:%s' "$kind" "$$" "${RANDOM:-0}"
}

popup_state() {
    tmux_option "$JOT_POPUP_STATE_KEY" ""
}

set_popup_state() {
    local token="$1"
    local kind="$2"
    local owner_pid="$3"

    tmux set-option -gq "$JOT_POPUP_STATE_KEY" "${token}|${kind}|${owner_pid}|${SOURCE_CLIENT}"
    debug_log "popup state set: client=$SOURCE_CLIENT kind=$kind token=$token pid=$owner_pid"
}

clear_popup_state() {
    tmux set-option -guq "$JOT_POPUP_STATE_KEY" 2>/dev/null || tmux set-option -gq "$JOT_POPUP_STATE_KEY" ""
}

clear_popup_state_if_token() {
    local token="$1"
    local state
    local state_token

    [ -n "$token" ] || return 0

    state="$(popup_state)"
    [ -n "$state" ] || return 0

    state_token="${state%%|*}"
    if [ "$state_token" = "$token" ]; then
        debug_log "popup state clear: client=$SOURCE_CLIENT token=$token"
        clear_popup_state
    fi
}

cleanup_active_popup_state() {
    clear_popup_state_if_token "${ACTIVE_POPUP_TOKEN:-}"
}

begin_popup_lifecycle() {
    local kind="$1"
    local token

    token="$(new_popup_token "$kind")"
    set_popup_state "$token" "$kind" "$$"
    ACTIVE_POPUP_TOKEN="$token"
    trap cleanup_active_popup_state EXIT
    trap 'exit 0' HUP INT TERM
}

popup_state_is_active() {
    local state="$1"
    local token
    local rest
    local kind
    local owner_pid

    [ -n "$state" ] || return 1

    token="${state%%|*}"
    rest="${state#*|}"
    [ "$rest" != "$state" ] || return 1
    [[ "$rest" == *"|"* ]] || return 1

    kind="${rest%%|*}"
    rest="${rest#*|}"
    owner_pid="${rest%%|*}"

    [ -n "$token" ] || return 1
    [ -n "$kind" ] || return 1
    case "$owner_pid" in
    "" | *[!0-9]*) return 1 ;;
    esac

    kill -0 "$owner_pid" 2>/dev/null
}

popup_state_client() {
    local state="$1"
    local rest

    [ -n "$state" ] || return 1
    [[ "$state" == *"|"* ]] || return 1

    rest="${state#*|}"
    [[ "$rest" == *"|"* ]] || return 1

    rest="${rest#*|}"
    [[ "$rest" == *"|"* ]] || return 1

    printf '%s' "${rest#*|}"
}

popup_client_from_option_key() {
    local option="$1"
    local safe
    local pts

    [[ "$option" == @jot_popup_* ]] || return 1
    safe="${option#@jot_popup_}"

    case "$safe" in
    _dev_pts_*)
        pts="${safe#_dev_pts_}"
        case "$pts" in
        "" | *[!0-9]*) return 1 ;;
        esac
        printf '/dev/pts/%s' "$pts"
        ;;
    *)
        return 1
        ;;
    esac
}

active_popup_client_from_any_state() {
    local line
    local option
    local state
    local client

    while IFS= read -r line; do
        option="${line%% *}"
        [ "$option" != "$line" ] || continue
        [[ "$option" == @jot_popup_* ]] || continue

        state="${line#* }"
        if popup_state_is_active "$state"; then
            client="$(popup_state_client "$state" 2>/dev/null || true)"
            if [ -z "$client" ]; then
                client="$(popup_client_from_option_key "$option" 2>/dev/null || true)"
            fi
            if [ -n "$client" ]; then
                printf '%s' "$client"
                return 0
            fi
        fi
    done < <(tmux show-options -gq 2>/dev/null || true)

    return 1
}

jot_popup_is_open() {
    local state

    state="$(popup_state)"
    [ -n "$state" ] || return 1

    if popup_state_is_active "$state"; then
        return 0
    fi

    debug_log "stale popup state cleared: client=$SOURCE_CLIENT state=$state"
    clear_popup_state
    return 1
}

toggle_popup_off_if_open() {
    if ! jot_popup_is_open; then
        return 1
    fi

    debug_log "toggle off: closing popup for client=$SOURCE_CLIENT"
    close_popup "$SOURCE_CLIENT"
    clear_popup_state
    return 0
}

normalize_popup_status() {
    local status="$1"

    case "$status" in
    0 | 129 | 130 | 143) return 0 ;;
    *) return "$status" ;;
    esac
}

display_popup() {
    local client="$1"
    local width="$2"
    local height="$3"
    local pos_x="$4"
    local pos_y="$5"
    local title="$6"
    local command="$7"
    local popup_status
    local popup_args=(display-popup)

    [ -z "$client" ] || popup_args+=(-c "$client")
    popup_args+=(
        -b "$BORDER_STYLE"
        -S "fg=$BORDER_COLOR"
        -w "$width"
        -h "$height"
        -x "$pos_x"
        -y "$pos_y"
        -T "$title"
        -E "$command"
    )

    debug_log "display_popup execution: ${popup_args[*]}"
    tmux "${popup_args[@]}"
    popup_status=$?
    debug_log "display_popup exit: status=$popup_status"

    return 0
}

close_popup_if_present() {
    local client="${1:-$CURRENT_CLIENT}"

    if [ -n "$client" ]; then
        tmux display-popup -c "$client" -C 2>/dev/null
    else
        tmux display-popup -C 2>/dev/null
    fi
}

close_popup() {
    close_popup_if_present "$@" || true
}

display_picker_popup() {
    local command
    command="$(shell_join "$SCRIPT_PATH" popup_picker "$SOURCE_CLIENT" "$SESSION_NAME")"
    display_popup "$SOURCE_CLIENT" "$PICKER_WIDTH" "$PICKER_HEIGHT" "$PICKER_X" "$PICKER_Y" "$PICKER_TITLE" "$command"
}

popup_editor_command() {
    shell_join "$SCRIPT_PATH" popup_editor "$SOURCE_CLIENT" "$SESSION_NAME"
}

display_editor_popup() {
    display_popup "$SOURCE_CLIENT" "$WIDTH" "$HEIGHT" "$POS_X" "$POS_Y" "$EDITOR_TITLE" "$(popup_editor_command)"
}

schedule_picker_popup() {
    local command
    command="$(shell_join "$SCRIPT_PATH" open_picker "$SOURCE_CLIENT" "$SESSION_NAME")"
    debug_log "Scheduling async picker open: $command"
    tmux run-shell -b "$command"
}

schedule_editor_popup() {
    local command
    command="$(shell_join "$SCRIPT_PATH" open_editor "$SOURCE_CLIENT" "$SESSION_NAME")"
    debug_log "Scheduling async editor open: $command"
    tmux run-shell -b "$command"
}

create_editor_session() {
    local command
    command="$(editor_command "$FILE_PATH")"
    debug_log "Creating hidden session $POPUP_SESSION with command: $command"
    tmux new-session -d -s "$POPUP_SESSION" "$command"
    set_hidden_session_options
}

select_note() {
    local fzf_out
    local fzf_status
    local query
    local selection
    local target_note

    fzf_out="$(list_notes | run_fzf)"
    fzf_status=$?

    if [ "$fzf_status" -ne 0 ] || [ -z "$fzf_out" ]; then
        debug_log "picker cancelled: status=$fzf_status session=$SESSION_NAME"
        exit 0
    fi

    query="$(printf '%s\n' "$fzf_out" | sed -n '1p' | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    selection="$(printf '%s\n' "$fzf_out" | sed -n '3p' | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [ -n "$selection" ]; then
        target_note="$selection"
        debug_log "User selected existing note: $target_note"
    else
        target_note="$query"
        debug_log "User wants to create new note from query: $target_note"
    fi

    target_note="${target_note%."$EXT"}"

    if ! note_name_is_valid "$target_note"; then
        message_client "invalid note name"
        debug_log "invalid note name: selected=$target_note session=$SESSION_NAME"
        exit 1
    fi

    SELECTED_NOTE="$target_note"
}

prepare_selected_note() {
    local target_file="$JOT_DIR/${SELECTED_NOTE}.${EXT}"

    if ! touch "$target_file" 2>/dev/null; then
        message_client "cannot create note: $target_file"
        debug_log "touch failed: target=$target_file session=$SESSION_NAME"
        exit 1
    fi

    if ! ln -sfn "$target_file" "$SESSION_LINK" 2>/dev/null; then
        message_client "cannot link session note: $SESSION_LINK -> $target_file"
        debug_log "link failed: source=$target_file target=$SESSION_LINK session=$SESSION_NAME"
        exit 1
    fi

    debug_log "selected note: session=$SESSION_NAME file=$target_file link=$SESSION_LINK"
}

# INIT
SOURCE_CLIENT="${2:-}"
SESSION_NAME="${3:-}"
RAW_SOURCE_CLIENT="$SOURCE_CLIENT"
RAW_SESSION_NAME="$SESSION_NAME"
CURRENT_CLIENT="$(tmux_format '#{client_name}')"
CURRENT_SESSION="$(tmux_format '#{session_name}')"
HIDDEN_PREFIX="$(tmux_option "@jot-hidden-session-prefix" "__tmux__jot_")"
DEBUG="$(tmux_option "@jot-debug" "off")"
LOG_FILE="$(expand_path "$(tmux_option "@jot-log-file" "$HOME/.local/state/tmux-jot.log")")"
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || printf '%s' "$0")"
IN_HIDDEN_SESSION=0

if is_true "$DEBUG"; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
fi

if [ -n "$CURRENT_SESSION" ] && [[ "$CURRENT_SESSION" == "$HIDDEN_PREFIX"* ]]; then
    IN_HIDDEN_SESSION=1

    SESSION_SOURCE_CLIENT="$(tmux_target_option "$CURRENT_SESSION" "@jot-source-client" "")"
    SESSION_ORIGIN="$(tmux_target_option "$CURRENT_SESSION" "@jot-origin-session" "")"

    if [ -z "$SESSION_SOURCE_CLIENT" ]; then
        SESSION_SOURCE_CLIENT="$(active_popup_client_from_any_state 2>/dev/null || true)"
    fi

    if [ -n "$SESSION_SOURCE_CLIENT" ]; then
        SOURCE_CLIENT="$SESSION_SOURCE_CLIENT"
    fi

    if [ -n "$SESSION_ORIGIN" ] && { [ -z "$SESSION_NAME" ] || [[ "$SESSION_NAME" == "$HIDDEN_PREFIX"* ]]; }; then
        SESSION_NAME="$SESSION_ORIGIN"
    fi
fi

[ -n "$SOURCE_CLIENT" ] || SOURCE_CLIENT="$CURRENT_CLIENT"

SAFE_CLIENT="$(printf '%s' "$SOURCE_CLIENT" | sed 's/[^A-Za-z0-9_-]/_/g')"
JOT_POPUP_STATE_KEY="@jot_popup_$SAFE_CLIENT"
ACTIVE_POPUP_TOKEN=""
trap cleanup_active_popup_state EXIT

if [ "$MODE" = "main" ] && [ "$IN_HIDDEN_SESSION" = "1" ]; then
    debug_log "toggle off from hidden session: closing popup for source_client=$SOURCE_CLIENT current_client=$CURRENT_CLIENT"
    close_popup "$SOURCE_CLIENT"
    clear_popup_state
    exit 0
fi

# SESSION MEMORY MANAGEMENT
if [ -n "$CURRENT_SESSION" ]; then
    if [[ "$CURRENT_SESSION" != "$HIDDEN_PREFIX"* ]]; then
        # normal session
        tmux set-option -gq "@jot_origin_$SAFE_CLIENT" "$CURRENT_SESSION"
        if [ -z "$SESSION_NAME" ] || [[ "$SESSION_NAME" == "$HIDDEN_PREFIX"* ]]; then
            SESSION_NAME="$CURRENT_SESSION"
        fi
    else
        # modes called from popup
        STORED_ORIGIN="$(tmux_option "@jot_origin_$SAFE_CLIENT" "")"
        if [ -n "$STORED_ORIGIN" ]; then
            if [ -z "$SESSION_NAME" ] || [[ "$SESSION_NAME" == "$HIDDEN_PREFIX"* ]]; then
                SESSION_NAME="$STORED_ORIGIN"
            fi
        else
            PARENT_SESSION="$(tmux_format '#{client_last_session}')"
            if [ -n "$PARENT_SESSION" ] && { [ -z "$SESSION_NAME" ] || [[ "$SESSION_NAME" == "$HIDDEN_PREFIX"* ]]; }; then
                SESSION_NAME="$PARENT_SESSION"
            fi
        fi
    fi
else
    # picker does not get his own session
    STORED_ORIGIN="$(tmux_option "@jot_origin_$SAFE_CLIENT" "")"
    if [ -n "$STORED_ORIGIN" ]; then
        if [ -z "$SESSION_NAME" ] || [[ "$SESSION_NAME" == "$HIDDEN_PREFIX"* ]]; then
            SESSION_NAME="$STORED_ORIGIN"
        fi
    fi
fi

if [ -z "$SESSION_NAME" ]; then
    message_client "cannot resolve source session"
    exit 1
fi

JOT_DIR="$(expand_path "$(tmux_option "@jot-dir" "$HOME/.local/share/tmux-jot")")"
if ! mkdir -p "$JOT_DIR" 2>/dev/null; then
    message_client "cannot create note directory: $JOT_DIR"
    exit 1
fi

EXT="$(normalize_extension "$(tmux_option "@jot-extension" "md")")"
SAFE_SESSION="$(safe_session_name "$SESSION_NAME")"
SESSION_KEY="${SAFE_SESSION}"
SESSION_DIR="$(expand_path "$(tmux_option "@jot-session-dir" "$JOT_DIR/.sessions")")"

if ! mkdir -p "$SESSION_DIR" 2>/dev/null; then
    message_client "cannot create session directory: $SESSION_DIR"
    exit 1
fi

SESSION_LINK="$SESSION_DIR/${SESSION_KEY}.${EXT}"

if [ -L "$SESSION_LINK" ]; then
    FILE_PATH="$(readlink "$SESSION_LINK")"
else
    FILE_PATH=""
fi

if [ -n "$FILE_PATH" ] && has_note_file "$FILE_PATH"; then
    NOTE_NAME="$(basename "$FILE_PATH" ".$EXT")"
    SAFE_NOTE_NAME="$(safe_session_name "$NOTE_NAME")"
    POPUP_SESSION="${HIDDEN_PREFIX}${SAFE_NOTE_NAME}"
else
    NOTE_NAME=""
    POPUP_SESSION="${HIDDEN_PREFIX}${SESSION_KEY}_picker"
fi

EDITOR_COMMAND="$(tmux_option "@jot-editor" "${EDITOR:-nvim}")"
COMMAND_SHELL="$(tmux_option "@jot-shell" "/bin/bash")"
FZF_COMMAND="$(tmux_option "@jot-fzf-command" "fzf")"
FZF_OPTIONS="$(tmux_option "@jot-fzf-options" "")"

BORDER_COLOR="$(tmux_option "@jot-border-color" "#b38d59")"
BORDER_STYLE="$(tmux_option "@jot-border-style" "rounded")"

WIDTH="$(tmux_option "@jot-popup-width" "40%")"
HEIGHT="$(tmux_option "@jot-popup-height" "50%")"
POS_X="$(tmux_option "@jot-popup-x" "100%")"
POS_Y="$(tmux_option "@jot-popup-y" "0")"

if [ "$POS_X" = "R" ] || [ "$POS_X" = "r" ]; then
    POS_X="100%"
fi

PICKER_WIDTH="$(tmux_option "@jot-picker-width" "50%")"
PICKER_HEIGHT="$(tmux_option "@jot-picker-height" "50%")"
PICKER_X="$(tmux_option "@jot-picker-x" "C")"
PICKER_Y="$(tmux_option "@jot-picker-y" "C")"

ICON="$(tmux_option "@jot-title-icon" "📝")"
EDITOR_TITLE="$(tmux_title "$(render_template "$(tmux_option "@jot-title" " {icon} {note} ")")")"
PICKER_TITLE="$(tmux_title "$(render_template "$(tmux_option "@jot-picker-title" " tmux-jot ")")")"
FZF_PROMPT="$(render_template "$(tmux_option "@jot-fzf-prompt" "{icon} Wybierz / Utwórz: ")")"

debug_log "--- EXEC START --- mode=$MODE raw_client=$RAW_SOURCE_CLIENT cur_client=$CURRENT_CLIENT source_client=$SOURCE_CLIENT cur_sess=$CURRENT_SESSION raw_sess=$RAW_SESSION_NAME src_sess=$SESSION_NAME file=$FILE_PATH popup=$POPUP_SESSION safe_client=$SAFE_CLIENT hidden=$IN_HIDDEN_SESSION"

case "$MODE" in
popup_picker)
    begin_popup_lifecycle "picker"
    select_note
    prepare_selected_note

    schedule_editor_popup
    exit 0
    ;;

popup_editor)
    begin_popup_lifecycle "editor"
    tmux attach-session -t "$POPUP_SESSION" 2>/dev/null || true
    exit 0
    ;;

open_picker)
    if ! display_picker_popup 2>/dev/null; then
        if close_popup_if_present "$SOURCE_CLIENT"; then
            clear_popup_state
            schedule_picker_popup
            exit 0
        fi

        message_client "cannot open picker popup"
        debug_log "CRITICAL: picker popup failed in open_picker mode"
        exit 1
    fi
    ;;

open_editor)
    if ! tmux has-session -t "$POPUP_SESSION" 2>/dev/null; then
        create_editor_session
    else
        set_hidden_session_options
    fi

    if ! display_editor_popup 2>/dev/null; then
        message_client "cannot open editor popup"
        debug_log "CRITICAL: editor popup failed in open_editor"
        exit 1
    fi
    ;;

switch | search)
    close_popup "$SOURCE_CLIENT"
    clear_popup_state
    schedule_picker_popup
    exit 0
    ;;

main)
    if toggle_popup_off_if_open; then
        exit 0
    fi

    if has_note_file "$FILE_PATH"; then
        if ! tmux has-session -t "$POPUP_SESSION" 2>/dev/null; then
            if ! create_editor_session 2>/dev/null; then
                message_client "cannot create editor session"
                debug_log "CRITICAL: create editor session failed"
                exit 1
            fi
        else
            set_hidden_session_options
        fi

        if ! display_editor_popup 2>/dev/null; then
            if close_popup_if_present "$SOURCE_CLIENT"; then
                clear_popup_state
                exit 0
            fi

            message_client "cannot open editor popup"
            debug_log "CRITICAL: editor popup failed"
            exit 1
        fi
    else
        if tmux has-session -t "$POPUP_SESSION" 2>/dev/null; then
            tmux kill-session -t "$POPUP_SESSION" 2>/dev/null || true
        fi

        if ! display_picker_popup 2>/dev/null; then
            if close_popup_if_present "$SOURCE_CLIENT"; then
                clear_popup_state
                exit 0
            fi

            message_client "cannot open picker popup"
            debug_log "CRITICAL: picker popup failed"
            exit 1
        fi
    fi
    ;;

*)
    message_client "unknown mode: $MODE"
    exit 2
    ;;
esac
