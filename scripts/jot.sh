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

editor_title() {
    tmux_title "$(render_template "$TITLE_TEMPLATE")"
}

fzf_prompt() {
    render_template "$FZF_PROMPT_TEMPLATE"
}

content_search_prompt() {
    render_template "$CONTENT_SEARCH_PROMPT_TEMPLATE"
}

display_picker_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" popup_picker "$SOURCE_CLIENT" "$SESSION_NAME")"
    display_popup "$SOURCE_CLIENT" "$WIDTH" "$HEIGHT" "$POS_X" "$POS_Y" "$(editor_title)" "$command"
}

display_content_search_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" popup_content_search "$SOURCE_CLIENT" "$SESSION_NAME")"
    display_popup "$SOURCE_CLIENT" "$WIDTH" "$HEIGHT" "$POS_X" "$POS_Y" "$(editor_title)" "$command"
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

display_editor_popup() {
    display_popup "$SOURCE_CLIENT" "$WIDTH" "$HEIGHT" "$POS_X" "$POS_Y" "$(editor_title)" "$(popup_editor_command)"
}

schedule_content_search_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" open_content_search "$SOURCE_CLIENT" "$SESSION_NAME")"
    debug_log "Scheduling async content search open: $command"
    tmux run-shell -b "$command"
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

run_fzf() {
    local prompt_quoted
    local script

    printf -v prompt_quoted '%q' "$(fzf_prompt)"
    script="exec $FZF_COMMAND $FZF_OPTIONS --prompt=$prompt_quoted --print-query --expect=enter"

    "$COMMAND_SHELL" -c "$script"
}

command_binary() {
    local command="$RG_COMMAND"

    if [ "$#" -gt 0 ]; then
        command="$1"
    fi
    command="${command%% *}"
    printf '%s' "$command"
}

run_content_fzf() {
    local rg_bin
    local dir_quoted
    local glob_quoted
    local prompt_quoted
    local preview_window_quoted
    local reload_command
    local preview_command
    local start_bind_quoted
    local change_bind_quoted
    local preview_command_quoted
    local script

    rg_bin="$(command_binary "$RG_COMMAND")"
    if ! command -v "$rg_bin" >/dev/null 2>&1; then
        message_client "ripgrep not found: $rg_bin"
        debug_log "content search failed: rg command not found: $rg_bin"
        exit 1
    fi

    printf -v dir_quoted '%q' "$JOT_DIR"
    printf -v glob_quoted '%q' "*.$EXT"
    printf -v prompt_quoted '%q' "$(content_search_prompt)"
    printf -v preview_window_quoted '%q' "$CONTENT_SEARCH_PREVIEW_WINDOW"

    reload_command="[ -n {q} ] && $RG_COMMAND --line-number --column --no-heading --color=always --colors path:none --colors line:none --colors column:none --smart-case --glob $glob_quoted -- {q} $dir_quoted 2>/dev/null || true"
    preview_command="[ -n {q} ] && $RG_COMMAND --line-number --color=always --context 3 --smart-case -- {q} {1} 2>/dev/null || sed -n '1,120p' {1} 2>/dev/null"

    printf -v start_bind_quoted '%q' "start:reload:$reload_command"
    printf -v change_bind_quoted '%q' "change:reload:$reload_command"
    printf -v preview_command_quoted '%q' "$preview_command"

    script="exec $FZF_COMMAND $FZF_OPTIONS --ansi --disabled --delimiter=: --nth=4.. --prompt=$prompt_quoted --print-query --expect=enter --bind=$start_bind_quoted --bind=$change_bind_quoted --preview=$preview_command_quoted --preview-window=$preview_window_quoted"
    "$COMMAND_SHELL" -c "$script"
}

select_content_match() {
    local fzf_out
    local fzf_status
    local line
    local line_no=0
    local query=""
    local selection=""
    local target_file

    fzf_out="$(run_content_fzf)"
    fzf_status=$?

    if [ "$fzf_status" -ne 0 ] || [ -z "$fzf_out" ]; then
        debug_log "content search cancelled: status=$fzf_status session=$SESSION_NAME"
        exit 0
    fi

    while IFS= read -r line; do
        line_no=$((line_no + 1))
        case "$line_no" in
        1) query="$(trim_space "$line")" ;;
        3)
            selection="$line"
            break
            ;;
        esac
    done <<<"$fzf_out"

    if [ -z "$selection" ]; then
        debug_log "content search empty selection: query=$query session=$SESSION_NAME"
        exit 0
    fi

    target_file="${selection%%:*}"
    if ! has_note_file "$target_file"; then
        message_client "selected search result is missing"
        debug_log "content search missing file: selected=$selection target=$target_file session=$SESSION_NAME"
        exit 1
    fi

    set_note_context_from_file "$target_file"
    debug_log "content search selected: query=$query session=$SESSION_NAME file=$FILE_PATH note=$NOTE_NAME"
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

open_picker() {
    resolve_note_context
    display_picker_popup
}

open_content_search() {
    resolve_note_context
    display_content_search_popup
}

open_doctor() {
    resolve_note_context
    display_doctor_popup
}

open_cleanup() {
    resolve_note_context
    display_cleanup_popup
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
