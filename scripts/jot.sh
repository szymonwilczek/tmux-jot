#!/usr/bin/env bash

set -u

MODE="${1:-main}"
RAW_SOURCE_CLIENT="${2:-}"
RAW_SESSION_NAME="${3:-}"
SEP=$'\036'

load_context_and_config() {
    local out
    local format

    format="#{client_name}${SEP}#{session_name}${SEP}#{@jot-hidden-session-prefix}${SEP}#{@jot-debug}${SEP}#{@jot-log-file}${SEP}#{@jot-dir}${SEP}#{@jot-extension}${SEP}#{@jot-session-dir}${SEP}#{@jot-editor}${SEP}#{@jot-shell}${SEP}#{@jot-fzf-command}${SEP}#{@jot-fzf-options}${SEP}#{@jot-sort-notes}${SEP}#{@jot-rg-command}${SEP}#{@jot-content-search-prompt}${SEP}#{@jot-content-search-preview-window}${SEP}#{@jot-border-color}${SEP}#{@jot-border-style}${SEP}#{@jot-popup-width}${SEP}#{@jot-popup-height}${SEP}#{@jot-popup-x}${SEP}#{@jot-popup-y}${SEP}#{@jot-title-icon}${SEP}#{@jot-title}${SEP}#{@jot-fzf-prompt}"
    out="$(tmux display-message -p "$format" 2>/dev/null || true)"

    IFS="$SEP" read -r \
        TMUX_CLIENT TMUX_SESSION CFG_HIDDEN_PREFIX CFG_DEBUG CFG_LOG_FILE \
        CFG_JOT_DIR CFG_EXT CFG_SESSION_DIR CFG_EDITOR CFG_SHELL \
        CFG_FZF_COMMAND CFG_FZF_OPTIONS CFG_SORT_NOTES CFG_RG_COMMAND \
        CFG_CONTENT_SEARCH_PROMPT CFG_CONTENT_SEARCH_PREVIEW_WINDOW \
        CFG_BORDER_COLOR CFG_BORDER_STYLE CFG_POPUP_WIDTH CFG_POPUP_HEIGHT CFG_POPUP_X CFG_POPUP_Y \
        CFG_ICON CFG_TITLE CFG_FZF_PROMPT <<<"$out"

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
    SORT_NOTES="${CFG_SORT_NOTES:-off}"
    RG_COMMAND="${CFG_RG_COMMAND:-rg}"
    CONTENT_SEARCH_PREVIEW_WINDOW="${CFG_CONTENT_SEARCH_PREVIEW_WINDOW:-right,60%,border-left}"

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
    if [ -n "$CFG_FZF_PROMPT" ]; then
        FZF_PROMPT_TEMPLATE="$CFG_FZF_PROMPT"
    else
        FZF_PROMPT_TEMPLATE='{icon} Wybierz / Utwórz: '
    fi
    if [ -n "$CFG_CONTENT_SEARCH_PROMPT" ]; then
        CONTENT_SEARCH_PROMPT_TEMPLATE="$CFG_CONTENT_SEARCH_PROMPT"
    else
        CONTENT_SEARCH_PROMPT_TEMPLATE='{icon} Szukaj w treści: '
    fi

    if [ "$POS_X" = "R" ] || [ "$POS_X" = "r" ]; then
        POS_X="100%"
    fi
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

editor_title() {
    tmux_title "$(render_template "$TITLE_TEMPLATE")"
}

fzf_prompt() {
    render_template "$FZF_PROMPT_TEMPLATE"
}

content_search_prompt() {
    render_template "$CONTENT_SEARCH_PROMPT_TEMPLATE"
}

popup_editor_command() {
    shell_join "$SCRIPT_PATH" popup_editor "$SOURCE_CLIENT" "$SESSION_NAME" "$POPUP_SESSION"
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

schedule_picker_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" open_picker "$SOURCE_CLIENT" "$SESSION_NAME")"
    debug_log "Scheduling async picker open: $command"
    tmux run-shell -b "$command"
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

print_notes() {
    local file
    local name

    shopt -s nullglob
    for file in "$JOT_DIR"/*."$EXT"; do
        [ -f "$file" ] || continue
        name="${file##*/}"
        printf '%s\n' "${name%."$EXT"}"
    done
    shopt -u nullglob
}

list_notes() {
    if is_true "$SORT_NOTES"; then
        print_notes | sort
    else
        print_notes
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

link_selected_note() {
    if ! ln -sfn "$FILE_PATH" "$SESSION_LINK" 2>/dev/null; then
        message_client "cannot link session note: $SESSION_LINK -> $FILE_PATH"
        debug_log "link failed: source=$FILE_PATH target=$SESSION_LINK session=$SESSION_NAME"
        exit 1
    fi
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

popup_state_kind() {
    local state="$1"
    local rest

    [ -n "$state" ] || return 1
    [[ "$state" == *"|"* ]] || return 1

    rest="${state#*|}"
    printf '%s' "${rest%%|*}"
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
