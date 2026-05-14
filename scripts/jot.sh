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

display_doctor_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" popup_doctor "$SOURCE_CLIENT" "$SESSION_NAME")"
    display_popup "$SOURCE_CLIENT" "$WIDTH" "$HEIGHT" "$POS_X" "$POS_Y" "$(editor_title)" "$command"
}

display_cleanup_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" popup_cleanup "$SOURCE_CLIENT" "$SESSION_NAME")"
    display_popup "$SOURCE_CLIENT" "$WIDTH" "$HEIGHT" "$POS_X" "$POS_Y" "$(editor_title)" "$command"
}

schedule_doctor_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" open_doctor "$SOURCE_CLIENT" "$SESSION_NAME")"
    debug_log "Scheduling async doctor open: $command"
    tmux run-shell -b "$command"
}

schedule_cleanup_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" open_cleanup "$SOURCE_CLIENT" "$SESSION_NAME")"
    debug_log "Scheduling async cleanup open: $command"
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

command_binary() {
    local command="$RG_COMMAND"

    if [ "$#" -gt 0 ]; then
        command="$1"
    fi
    command="${command%% *}"
    printf '%s' "$command"
}

doctor_command_line() {
    local label="$1"
    local command="$2"
    local binary
    local path

    binary="$(command_binary "$command")"
    path="$(command -v "$binary" 2>/dev/null || true)"
    if [ -n "$path" ]; then
        printf '  %-18s ok      %s\n' "$label" "$path"
    else
        printf '  %-18s missing %s\n' "$label" "$binary"
    fi
}

doctor_path_line() {
    local label="$1"
    local path="$2"
    local status="missing"

    [ -e "$path" ] && status="ok"
    printf '  %-18s %-7s %s\n' "$label" "$status" "$path"
}

doctor_hidden_sessions() {
    local line
    local session
    local windows
    local attached
    local count=0

    while IFS=$'\t' read -r session windows attached; do
        [[ "$session" == "$HIDDEN_PREFIX"* ]] || continue
        count=$((count + 1))
        printf '  %-30s windows=%s attached=%s\n' "$session" "$windows" "$attached"
    done < <(tmux list-sessions -F "#{session_name}"$'\t'"#{session_windows}"$'\t'"#{session_attached}" 2>/dev/null || true)

    if [ "$count" -eq 0 ]; then
        printf '  none\n'
    fi
}

doctor_popup_states() {
    local line
    local option
    local state
    local client
    local kind
    local status
    local count=0

    while IFS= read -r line; do
        option="${line%% *}"
        [ "$option" != "$line" ] || continue
        [[ "$option" == @jot_popup_* ]] || continue

        state="${line#* }"
        client="$(popup_state_client "$state" 2>/dev/null || true)"
        [ -n "$client" ] || client="$(popup_client_from_option_key "$option" 2>/dev/null || true)"
        kind="$(popup_state_kind "$state" 2>/dev/null || true)"
        if popup_state_is_active "$state"; then
            status="active"
        else
            status="stale"
        fi

        count=$((count + 1))
        printf '  %-7s %-14s client=%s option=%s\n' "$status" "${kind:-unknown}" "${client:-unknown}" "$option"
    done < <(tmux show-options -gq 2>/dev/null || true)

    if [ "$count" -eq 0 ]; then
        printf '  none\n'
    fi
}

print_doctor_report() {
    local tmux_version

    tmux_version="$(tmux -V 2>/dev/null || printf 'missing')"

    printf 'tmux-jot doctor\n'
    printf '===============\n\n'

    printf 'Context\n'
    printf '  %-18s %s\n' "mode" "$MODE"
    printf '  %-18s %s\n' "source client" "$SOURCE_CLIENT"
    printf '  %-18s %s\n' "tmux client" "$CURRENT_CLIENT"
    printf '  %-18s %s\n' "source session" "$SESSION_NAME"
    printf '  %-18s %s\n' "tmux session" "$CURRENT_SESSION"
    printf '  %-18s %s\n' "hidden prefix" "$HIDDEN_PREFIX"
    printf '\n'

    printf 'Versions and commands\n'
    printf '  %-18s %s\n' "tmux" "$tmux_version"
    doctor_command_line "editor" "$EDITOR_COMMAND"
    doctor_command_line "shell" "$COMMAND_SHELL"
    doctor_command_line "fzf" "$FZF_COMMAND"
    doctor_command_line "rg" "$RG_COMMAND"
    printf '\n'

    printf 'Paths\n'
    doctor_path_line "script" "$SCRIPT_PATH"
    doctor_path_line "jot dir" "$JOT_DIR"
    doctor_path_line "session dir" "$SESSION_DIR"
    doctor_path_line "session link" "$SESSION_LINK"
    if [ -n "$FILE_PATH" ]; then
        doctor_path_line "note file" "$FILE_PATH"
    else
        printf '  %-18s none\n' "note file"
    fi
    printf '  %-18s %s\n' "log file" "$LOG_FILE"
    printf '\n'

    printf 'Config\n'
    printf '  %-18s %s\n' "debug" "$DEBUG"
    printf '  %-18s %s\n' "extension" "$EXT"
    printf '  %-18s %s\n' "sort notes" "$SORT_NOTES"
    printf '  %-18s %s\n' "popup size" "$WIDTH x $HEIGHT"
    printf '  %-18s %s,%s\n' "popup pos" "$POS_X" "$POS_Y"
    printf '\n'

    printf 'Hidden sessions\n'
    doctor_hidden_sessions
    printf '\n'

    printf 'Popup states\n'
    doctor_popup_states
}

print_cleanup_report() {
    local session
    local attached
    local killed=0
    local skipped=0
    local failed=0

    printf 'tmux-jot cleanup\n'
    printf '================\n\n'
    printf 'Killing detached hidden sessions matching %s*\n\n' "$HIDDEN_PREFIX"

    while IFS=$'\t' read -r session attached; do
        [[ "$session" == "$HIDDEN_PREFIX"* ]] || continue

        if [ "${attached:-0}" != "0" ]; then
            skipped=$((skipped + 1))
            printf '  skip  %-30s attached=%s\n' "$session" "$attached"
            continue
        fi

        if tmux kill-session -t "$session" 2>/dev/null; then
            killed=$((killed + 1))
            printf '  kill  %s\n' "$session"
        else
            failed=$((failed + 1))
            printf '  fail  %s\n' "$session"
        fi
    done < <(tmux list-sessions -F "#{session_name}"$'\t'"#{session_attached}" 2>/dev/null || true)

    if [ "$killed" -eq 0 ] && [ "$skipped" -eq 0 ] && [ "$failed" -eq 0 ]; then
        printf '  none\n'
    fi

    printf '\nSummary\n'
    printf '  killed  %s\n' "$killed"
    printf '  skipped %s\n' "$skipped"
    printf '  failed  %s\n' "$failed"
}

wait_for_key() {
    printf '\nPress any key to close...'
    IFS= read -r -n 1 REPLY || true
    printf '\n'
}

open_doctor() {
    resolve_note_context
    display_doctor_popup
}

open_cleanup() {
    resolve_note_context
    display_cleanup_popup
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
