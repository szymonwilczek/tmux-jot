#!/usr/bin/env bash

set -u

MODE="${1:-main}"
RAW_SOURCE_CLIENT="${2:-}"
RAW_SESSION_NAME="${3:-}"
SEP=$'\036'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

script_path() {
    local path="${BASH_SOURCE[0]}"

    case "$path" in
    /*) printf '%s' "$path" ;;
    *) printf '%s/%s' "$PWD" "$path" ;;
    esac
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

command_binary() {
    local command="$RG_COMMAND"

    if [ "$#" -gt 0 ]; then
        command="$1"
    fi
    command="${command%% *}"
    printf '%s' "$command"
}

doctor_path_line() {
    local label="$1"
    local path="$2"
    local status="missing"

    [ -e "$path" ] && status="ok"
    printf '  %-18s %-7s %s\n' "$label" "$status" "$path"
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

content_search)
    close_popup "$SOURCE_CLIENT"
    clear_popup_state
    schedule_content_search_popup
    ;;

doctor)
    close_popup "$SOURCE_CLIENT"
    clear_popup_state
    schedule_doctor_popup
    ;;

cleanup)
    close_popup "$SOURCE_CLIENT"
    clear_popup_state
    schedule_cleanup_popup
    ;;

open_picker)
    open_picker
    ;;

open_content_search)
    open_content_search
    ;;

open_doctor)
    open_doctor
    ;;

open_cleanup)
    open_cleanup
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

popup_content_search)
    resolve_note_context
    begin_popup_lifecycle "content_search"
    select_content_match
    link_selected_note
    schedule_editor_popup "$FILE_PATH" "$NOTE_NAME"
    ;;

popup_doctor)
    resolve_note_context
    begin_popup_lifecycle "doctor"
    print_doctor_report
    wait_for_key
    ;;

popup_cleanup)
    resolve_note_context
    begin_popup_lifecycle "cleanup"
    print_cleanup_report
    wait_for_key
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
