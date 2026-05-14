#!/usr/bin/env bash

set -u

MODE="${1:-main}"
RAW_SOURCE_CLIENT="${2:-}"
RAW_SESSION_NAME="${3:-}"
SEP=$'\036'

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

safe_name() {
    local input="$1"
    local safe

    safe="${input//[^A-Za-z0-9_-]/_}"
    [ -n "$safe" ] || safe="session"
    printf '%s' "$safe"
}

trim_space() {
    local value="$1"

    value="${value//$'\r'/}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

is_true() {
    case "${1:-}" in
    1 | on | true | yes | y) return 0 ;;
    *) return 1 ;;
    esac
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

tmux_title() {
    printf '%s' "${1//#/##}"
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

load_context_and_config() {
    local out
    local format

    format="#{client_name}${SEP}#{session_name}${SEP}#{@jot-hidden-session-prefix}${SEP}#{@jot-debug}${SEP}#{@jot-log-file}${SEP}#{@jot-dir}${SEP}#{@jot-extension}${SEP}#{@jot-session-dir}${SEP}#{@jot-editor}${SEP}#{@jot-shell}${SEP}#{@jot-fzf-command}${SEP}#{@jot-fzf-options}${SEP}#{@jot-border-color}${SEP}#{@jot-border-style}${SEP}#{@jot-popup-width}${SEP}#{@jot-popup-height}${SEP}#{@jot-popup-x}${SEP}#{@jot-popup-y}${SEP}#{@jot-picker-width}${SEP}#{@jot-picker-height}${SEP}#{@jot-picker-x}${SEP}#{@jot-picker-y}${SEP}#{@jot-title-icon}${SEP}#{@jot-title}${SEP}#{@jot-picker-title}${SEP}#{@jot-fzf-prompt}"
    out="$(tmux display-message -p "$format" 2>/dev/null || true)"

    IFS="$SEP" read -r \
        TMUX_CLIENT TMUX_SESSION CFG_HIDDEN_PREFIX CFG_DEBUG CFG_LOG_FILE \
        CFG_JOT_DIR CFG_EXT CFG_SESSION_DIR CFG_EDITOR CFG_SHELL \
        CFG_FZF_COMMAND CFG_FZF_OPTIONS CFG_BORDER_COLOR CFG_BORDER_STYLE \
        CFG_POPUP_WIDTH CFG_POPUP_HEIGHT CFG_POPUP_X CFG_POPUP_Y \
        CFG_PICKER_WIDTH CFG_PICKER_HEIGHT CFG_PICKER_X CFG_PICKER_Y \
        CFG_ICON CFG_TITLE CFG_PICKER_TITLE CFG_FZF_PROMPT <<<"$out"

    CURRENT_CLIENT="${RAW_SOURCE_CLIENT:-$TMUX_CLIENT}"
    CURRENT_SESSION="${RAW_SESSION_NAME:-$TMUX_SESSION}"
    SOURCE_CLIENT="$CURRENT_CLIENT"
    SESSION_NAME="$CURRENT_SESSION"

    HIDDEN_PREFIX="${CFG_HIDDEN_PREFIX:-__tmux__jot_}"
    DEBUG="${CFG_DEBUG:-off}"
    LOG_FILE="$(expand_path "${CFG_LOG_FILE:-$HOME/.local/state/tmux-jot.log}")"

    JOT_DIR_RAW="${CFG_JOT_DIR:-$HOME/.local/share/tmux-jot}"
    EXT_RAW="${CFG_EXT:-md}"
    EXT="$(normalize_extension "$EXT_RAW")"
    SESSION_DIR_RAW="${CFG_SESSION_DIR:-}"

    EDITOR_COMMAND="${CFG_EDITOR:-${EDITOR:-nvim}}"
    COMMAND_SHELL="${CFG_SHELL:-/bin/bash}"
    FZF_COMMAND="${CFG_FZF_COMMAND:-fzf}"
    FZF_OPTIONS="${CFG_FZF_OPTIONS:-}"

    BORDER_COLOR="${CFG_BORDER_COLOR:-#b38d59}"
    BORDER_STYLE="${CFG_BORDER_STYLE:-rounded}"
    WIDTH="${CFG_POPUP_WIDTH:-40%}"
    HEIGHT="${CFG_POPUP_HEIGHT:-50%}"
    POS_X="${CFG_POPUP_X:-100%}"
    POS_Y="${CFG_POPUP_Y:-0}"

    ICON="${CFG_ICON:-📝}"
    if [ -n "$CFG_TITLE" ]; then
        TITLE_TEMPLATE="$CFG_TITLE"
    else
        TITLE_TEMPLATE=' {icon} {note} '
    fi
    PICKER_TITLE_TEMPLATE="${CFG_PICKER_TITLE:- tmux-jot }"
    if [ -n "$CFG_FZF_PROMPT" ]; then
        FZF_PROMPT_TEMPLATE="$CFG_FZF_PROMPT"
    else
        FZF_PROMPT_TEMPLATE='{icon} Wybierz / Utwórz: '
    fi

    if [ "$POS_X" = "R" ] || [ "$POS_X" = "r" ]; then
        POS_X="100%"
    fi

    PICKER_WIDTH="${CFG_PICKER_WIDTH:-$WIDTH}"
    PICKER_HEIGHT="${CFG_PICKER_HEIGHT:-$HEIGHT}"
    PICKER_X="${CFG_PICKER_X:-$POS_X}"
    PICKER_Y="${CFG_PICKER_Y:-$POS_Y}"

    if [ "$PICKER_X" = "R" ] || [ "$PICKER_X" = "r" ]; then
        PICKER_X="100%"
    fi
}

setup_debug_log() {
    local dir

    is_true "$DEBUG" || return 0

    dir="${LOG_FILE%/*}"
    [ "$dir" != "$LOG_FILE" ] || dir="."
    mkdir -p "$dir" 2>/dev/null || true
}

debug_log() {
    local message="$1"

    is_true "$DEBUG" || return 0
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >>"$LOG_FILE" 2>/dev/null || true
}

script_path() {
    local path="${BASH_SOURCE[0]}"

    case "$path" in
    /*) printf '%s' "$path" ;;
    *) printf '%s/%s' "$PWD" "$path" ;;
    esac
}

message_client() {
    local message="$1"

    if [ -n "${SOURCE_CLIENT:-}" ]; then
        tmux display-message -c "$SOURCE_CLIENT" "tmux-jot: $message" 2>/dev/null || true
    else
        tmux display-message "tmux-jot: $message" 2>/dev/null || true
    fi
}

has_note_file() {
    [ -n "${1:-}" ] && [ -e "$1" ]
}

note_name_is_valid() {
    local name="$1"

    [ -n "$name" ] || return 1
    [[ "$name" != *"/"* ]] || return 1
    [[ "$name" != *$'\n'* ]] || return 1
    [[ "$name" != *$'\r'* ]] || return 1
    return 0
}

render_template() {
    local template="$1"

    template="${template//\{icon\}/$ICON}"
    template="${template//\{session\}/$SESSION_NAME}"
    template="${template//\{note\}/${NOTE_NAME:-$SESSION_NAME}}"
    template="${template//\{file\}/$FILE_PATH}"
    printf '%s' "$template"
}

ensure_storage() {
    [ "${STORAGE_READY:-0}" = "1" ] && return 0

    JOT_DIR="$(expand_path "$JOT_DIR_RAW")"
    if ! mkdir -p "$JOT_DIR" 2>/dev/null; then
        message_client "cannot create note directory: $JOT_DIR"
        exit 1
    fi

    if [ -n "$SESSION_DIR_RAW" ]; then
        SESSION_DIR="$(expand_path "$SESSION_DIR_RAW")"
    else
        SESSION_DIR="$JOT_DIR/.sessions"
    fi

    if ! mkdir -p "$SESSION_DIR" 2>/dev/null; then
        message_client "cannot create session directory: $SESSION_DIR"
        exit 1
    fi

    STORAGE_READY=1
}

set_note_context_from_file() {
    local file="$1"
    local note="${2:-}"
    local base

    FILE_PATH="$file"
    if [ -n "$note" ]; then
        NOTE_NAME="$note"
    else
        base="${FILE_PATH##*/}"
        NOTE_NAME="${base%."$EXT"}"
    fi

    SAFE_NOTE_NAME="$(safe_name "$NOTE_NAME")"
    POPUP_SESSION="${HIDDEN_PREFIX}${SAFE_NOTE_NAME}"
}

resolve_note_context() {
    local base

    ensure_storage

    SAFE_SESSION="$(safe_name "$SESSION_NAME")"
    SESSION_LINK="$SESSION_DIR/${SAFE_SESSION}.${EXT}"
    FILE_PATH=""
    NOTE_NAME=""

    if [ -L "$SESSION_LINK" ]; then
        FILE_PATH="$(readlink "$SESSION_LINK" 2>/dev/null || true)"
    fi

    if has_note_file "$FILE_PATH"; then
        base="${FILE_PATH##*/}"
        NOTE_NAME="${base%."$EXT"}"
        SAFE_NOTE_NAME="$(safe_name "$NOTE_NAME")"
        POPUP_SESSION="${HIDDEN_PREFIX}${SAFE_NOTE_NAME}"
    else
        POPUP_SESSION="${HIDDEN_PREFIX}${SAFE_SESSION}_picker"
    fi
}

popup_state() {
    tmux show-option -gqv "$JOT_POPUP_STATE_KEY" 2>/dev/null || true
}

set_popup_state() {
    local token="$1"
    local kind="$2"
    local owner_pid="$3"

    tmux set-option -gq "$JOT_POPUP_STATE_KEY" "${token}|${kind}|${owner_pid}|${SOURCE_CLIENT}" 2>/dev/null || true
    debug_log "popup state set: client=$SOURCE_CLIENT kind=$kind token=$token pid=$owner_pid"
}

clear_popup_state() {
    tmux set-option -guq "$JOT_POPUP_STATE_KEY" 2>/dev/null || tmux set-option -gq "$JOT_POPUP_STATE_KEY" "" 2>/dev/null || true
}

clear_popup_state_if_token() {
    local token="$1"
    local state

    [ -n "$token" ] || return 0

    state="$(popup_state)"
    [ -n "$state" ] || return 0

    if [ "${state%%|*}" = "$token" ]; then
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

    token="${kind}:$$:${RANDOM:-0}"
    set_popup_state "$token" "$kind" "$$"
    ACTIVE_POPUP_TOKEN="$token"
    trap cleanup_active_popup_state EXIT
    trap 'exit 0' HUP INT TERM
}

popup_state_owner_pid() {
    local state="$1"
    local rest
    local owner_pid

    [ -n "$state" ] || return 1
    [[ "$state" == *"|"* ]] || return 1

    rest="${state#*|}"
    [[ "$rest" == *"|"* ]] || return 1

    rest="${rest#*|}"
    owner_pid="${rest%%|*}"
    case "$owner_pid" in
    "" | *[!0-9]*) return 1 ;;
    esac

    printf '%s' "$owner_pid"
}

popup_state_is_active() {
    local owner_pid

    owner_pid="$(popup_state_owner_pid "$1" 2>/dev/null || true)"
    [ -n "$owner_pid" ] || return 1
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
    *) return 1 ;;
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
            [ -n "$client" ] || client="$(popup_client_from_option_key "$option" 2>/dev/null || true)"
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

toggle_popup_off_if_open() {
    if ! jot_popup_is_open; then
        return 1
    fi

    debug_log "toggle off: closing popup for client=$SOURCE_CLIENT"
    close_popup "$SOURCE_CLIENT"
    clear_popup_state
    return 0
}

load_hidden_context() {
    local source_client
    local origin_session

    source_client="$(tmux_target_option "$CURRENT_SESSION" "@jot-source-client" "")"
    origin_session="$(tmux_target_option "$CURRENT_SESSION" "@jot-origin-session" "")"

    if [ -z "$source_client" ]; then
        source_client="$(active_popup_client_from_any_state 2>/dev/null || true)"
    fi

    [ -z "$source_client" ] || SOURCE_CLIENT="$source_client"
    if [ -n "$origin_session" ] && { [ -z "$SESSION_NAME" ] || [[ "$SESSION_NAME" == "$HIDDEN_PREFIX"* ]]; }; then
        SESSION_NAME="$origin_session"
    fi
}

resolve_source_context() {
    IN_HIDDEN_SESSION=0

    if [ -n "$CURRENT_SESSION" ] && [[ "$CURRENT_SESSION" == "$HIDDEN_PREFIX"* ]]; then
        IN_HIDDEN_SESSION=1
        load_hidden_context
    fi

    [ -n "$SOURCE_CLIENT" ] || SOURCE_CLIENT="$CURRENT_CLIENT"
    SAFE_CLIENT="$(safe_name "$SOURCE_CLIENT")"
    JOT_POPUP_STATE_KEY="@jot_popup_$SAFE_CLIENT"
    ACTIVE_POPUP_TOKEN=""
}

resolve_origin_session() {
    local stored_origin
    local parent_session

    if [ -n "$CURRENT_SESSION" ]; then
        if [[ "$CURRENT_SESSION" != "$HIDDEN_PREFIX"* ]]; then
            tmux set-option -gq "@jot_origin_$SAFE_CLIENT" "$CURRENT_SESSION" 2>/dev/null || true
            if [ -z "$SESSION_NAME" ] || [[ "$SESSION_NAME" == "$HIDDEN_PREFIX"* ]]; then
                SESSION_NAME="$CURRENT_SESSION"
            fi
        else
            stored_origin="$(tmux show-option -gqv "@jot_origin_$SAFE_CLIENT" 2>/dev/null || true)"
            if [ -n "$stored_origin" ]; then
                if [ -z "$SESSION_NAME" ] || [[ "$SESSION_NAME" == "$HIDDEN_PREFIX"* ]]; then
                    SESSION_NAME="$stored_origin"
                fi
            else
                parent_session="$(tmux display-message -p '#{client_last_session}' 2>/dev/null || true)"
                if [ -n "$parent_session" ] && { [ -z "$SESSION_NAME" ] || [[ "$SESSION_NAME" == "$HIDDEN_PREFIX"* ]]; }; then
                    SESSION_NAME="$parent_session"
                fi
            fi
        fi
    else
        stored_origin="$(tmux show-option -gqv "@jot_origin_$SAFE_CLIENT" 2>/dev/null || true)"
        if [ -n "$stored_origin" ] && { [ -z "$SESSION_NAME" ] || [[ "$SESSION_NAME" == "$HIDDEN_PREFIX"* ]]; }; then
            SESSION_NAME="$stored_origin"
        fi
    fi

    if [ -z "$SESSION_NAME" ]; then
        message_client "cannot resolve source session"
        exit 1
    fi
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

picker_title() {
    tmux_title "$(render_template "$PICKER_TITLE_TEMPLATE")"
}

editor_title() {
    tmux_title "$(render_template "$TITLE_TEMPLATE")"
}

fzf_prompt() {
    render_template "$FZF_PROMPT_TEMPLATE"
}

popup_editor_command() {
    shell_join "$SCRIPT_PATH" popup_editor "$SOURCE_CLIENT" "$SESSION_NAME" "$POPUP_SESSION"
}

display_picker_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" popup_picker "$SOURCE_CLIENT" "$SESSION_NAME")"
    display_popup "$SOURCE_CLIENT" "$PICKER_WIDTH" "$PICKER_HEIGHT" "$PICKER_X" "$PICKER_Y" "$(picker_title)" "$command"
}

display_editor_popup() {
    display_popup "$SOURCE_CLIENT" "$WIDTH" "$HEIGHT" "$POS_X" "$POS_Y" "$(editor_title)" "$(popup_editor_command)"
}

schedule_picker_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" open_picker "$SOURCE_CLIENT" "$SESSION_NAME")"
    debug_log "Scheduling async picker open: $command"
    tmux run-shell -b "$command"
}

schedule_editor_popup() {
    local file="${1:-$FILE_PATH}"
    local note="${2:-$NOTE_NAME}"
    local command

    command="$(shell_join "$SCRIPT_PATH" open_editor "$SOURCE_CLIENT" "$SESSION_NAME" "$file" "$note")"
    debug_log "Scheduling async editor open: $command"
    tmux run-shell -b "$command"
}

editor_command() {
    local file="$1"
    local file_quoted

    printf -v file_quoted '%q' "$file"
    printf 'exec %s %s' "$EDITOR_COMMAND" "$file_quoted"
}

set_hidden_session_options() {
    tmux \
        set-option -t "$POPUP_SESSION" status off \; \
        set-option -t "$POPUP_SESSION" detach-on-destroy on \; \
        set-option -t "$POPUP_SESSION" @jot-source-client "$SOURCE_CLIENT" \; \
        set-option -t "$POPUP_SESSION" @jot-origin-session "$SESSION_NAME" \
        2>/dev/null || true
}

create_editor_session() {
    local command

    command="$(editor_command "$FILE_PATH")"
    debug_log "Creating hidden session $POPUP_SESSION with command: $command"
    tmux new-session -d -s "$POPUP_SESSION" "$command"
    set_hidden_session_options
}

ensure_editor_session() {
    if ! tmux has-session -t "$POPUP_SESSION" 2>/dev/null; then
        if ! create_editor_session 2>/dev/null; then
            message_client "cannot create editor session"
            debug_log "CRITICAL: create editor session failed"
            exit 1
        fi
    else
        set_hidden_session_options
    fi
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

    printf -v prompt_quoted '%q' "$(fzf_prompt)"
    script="exec $FZF_COMMAND $FZF_OPTIONS --prompt=$prompt_quoted --print-query --expect=enter"

    "$COMMAND_SHELL" -c "$script"
}

select_note() {
    local fzf_out
    local fzf_status
    local line
    local line_no=0
    local query=""
    local selection=""
    local target_note

    fzf_out="$(list_notes | run_fzf)"
    fzf_status=$?

    if [ "$fzf_status" -ne 0 ] || [ -z "$fzf_out" ]; then
        debug_log "picker cancelled: status=$fzf_status session=$SESSION_NAME"
        exit 0
    fi

    while IFS= read -r line; do
        line_no=$((line_no + 1))
        case "$line_no" in
        1) query="$(trim_space "$line")" ;;
        3)
            selection="$(trim_space "$line")"
            break
            ;;
        esac
    done <<<"$fzf_out"

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

    set_note_context_from_file "$target_file" "$SELECTED_NOTE"
    debug_log "selected note: session=$SESSION_NAME file=$FILE_PATH link=$SESSION_LINK"
}

open_picker() {
    resolve_note_context
    display_picker_popup
}

open_editor() {
    local file_arg="${1:-}"
    local note_arg="${2:-}"

    if [ -n "$file_arg" ] && has_note_file "$file_arg"; then
        set_note_context_from_file "$file_arg" "$note_arg"
    else
        resolve_note_context
    fi

    ensure_editor_session
    display_editor_popup
}

load_context_and_config
setup_debug_log

SCRIPT_PATH="$(script_path)"
STORAGE_READY=0
FILE_PATH=""
NOTE_NAME=""
POPUP_SESSION=""
SESSION_LINK=""
SAFE_SESSION=""

resolve_source_context
trap cleanup_active_popup_state EXIT

if [ "$MODE" = "main" ] && [ "$IN_HIDDEN_SESSION" = "1" ]; then
    debug_log "toggle off from hidden session: closing popup for source_client=$SOURCE_CLIENT current_client=$CURRENT_CLIENT"
    close_popup "$SOURCE_CLIENT"
    clear_popup_state
    exit 0
fi

if [ "$MODE" = "main" ] && toggle_popup_off_if_open; then
    exit 0
fi

resolve_origin_session

debug_log "--- EXEC START --- mode=$MODE raw_client=$RAW_SOURCE_CLIENT cur_client=$CURRENT_CLIENT source_client=$SOURCE_CLIENT cur_sess=$CURRENT_SESSION raw_sess=$RAW_SESSION_NAME src_sess=$SESSION_NAME hidden=$IN_HIDDEN_SESSION"

case "$MODE" in
main)
    resolve_note_context
    if has_note_file "$FILE_PATH"; then
        open_editor "$FILE_PATH" "$NOTE_NAME"
    else
        if tmux has-session -t "$POPUP_SESSION" 2>/dev/null; then
            tmux kill-session -t "$POPUP_SESSION" 2>/dev/null || true
        fi
        display_picker_popup
    fi
    ;;

switch | search)
    close_popup "$SOURCE_CLIENT"
    clear_popup_state
    schedule_picker_popup
    ;;

open_picker)
    open_picker
    ;;

open_editor)
    open_editor "${4:-}" "${5:-}"
    ;;

popup_picker)
    resolve_note_context
    begin_popup_lifecycle "picker"
    select_note
    prepare_selected_note
    schedule_editor_popup "$FILE_PATH" "$NOTE_NAME"
    ;;

popup_editor)
    POPUP_SESSION="${4:-}"
    if [ -z "$POPUP_SESSION" ]; then
        resolve_note_context
    fi
    begin_popup_lifecycle "editor"
    tmux attach-session -t "$POPUP_SESSION" 2>/dev/null || true
    ;;

*)
    message_client "unknown mode: $MODE"
    exit 2
    ;;
esac
