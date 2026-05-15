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

# order: helpers, loaded config, tmux state/context,
# note storage, popup rendering, session size, then feature modules

# shellcheck source=scripts/lib/util.sh
. "$SCRIPT_DIR/lib/util.sh"
# shellcheck source=scripts/lib/config.sh
. "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=scripts/lib/popup_state.sh
. "$SCRIPT_DIR/lib/popup_state.sh"
# shellcheck source=scripts/lib/context.sh
. "$SCRIPT_DIR/lib/context.sh"
# shellcheck source=scripts/lib/notes.sh
. "$SCRIPT_DIR/lib/notes.sh"
# shellcheck source=scripts/lib/popup.sh
. "$SCRIPT_DIR/lib/popup.sh"
# shellcheck source=scripts/lib/size.sh
. "$SCRIPT_DIR/lib/size.sh"
# shellcheck source=scripts/lib/editor.sh
. "$SCRIPT_DIR/lib/editor.sh"
# shellcheck source=scripts/lib/picker.sh
. "$SCRIPT_DIR/lib/picker.sh"
# shellcheck source=scripts/lib/content_search.sh
. "$SCRIPT_DIR/lib/content_search.sh"
# shellcheck source=scripts/lib/doctor.sh
. "$SCRIPT_DIR/lib/doctor.sh"
# shellcheck source=scripts/lib/cleanup.sh
. "$SCRIPT_DIR/lib/cleanup.sh"

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
apply_session_popup_size

debug_log "--- EXEC START --- mode=$MODE raw_client=$RAW_SOURCE_CLIENT cur_client=$CURRENT_CLIENT source_client=$SOURCE_CLIENT cur_sess=$CURRENT_SESSION raw_sess=$RAW_SESSION_NAME src_sess=$SESSION_NAME hidden=$IN_HIDDEN_SESSION size_delta=$POPUP_SIZE_DELTA size=$WIDTH x $HEIGHT"

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

resize_increase)
    resize_popup "increase"
    ;;

resize_decrease)
    resize_popup "decrease"
    ;;

resize_repeat_increase)
    resize_popup_repeat_or_send_key "increase" "${4:-=}"
    ;;

resize_repeat_decrease)
    resize_popup_repeat_or_send_key "decrease" "${4:--}"
    ;;

resize_reset)
    reset_popup_size
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
