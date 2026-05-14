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
}

attach_command() {
    shell_join tmux attach-session -t "$POPUP_SESSION"
}

display_popup() {
    local client="$1"
    local width="$2"
    local height="$3"
    local pos_x="$4"
    local pos_y="$5"
    local title="$6"
    local command="$7"
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
}

display_picker_popup() {
    local command
    command="$(shell_join "$SCRIPT_PATH" popup_picker "$SOURCE_CLIENT" "$SESSION_NAME")"
    display_popup "$SOURCE_CLIENT" "$PICKER_WIDTH" "$PICKER_HEIGHT" "$PICKER_X" "$PICKER_Y" "$PICKER_TITLE" "$command"
}

display_editor_popup() {
    display_popup "$SOURCE_CLIENT" "$WIDTH" "$HEIGHT" "$POS_X" "$POS_Y" "$EDITOR_TITLE" "$(attach_command)"
}

detach_current_client() {
    if [ -n "$CURRENT_CLIENT" ]; then
        tmux detach-client -t "$CURRENT_CLIENT" 2>/dev/null || tmux detach-client 2>/dev/null || true
    else
        tmux detach-client 2>/dev/null || true
    fi
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

    # FZF returns from --expect=enter:
    # 1. query
    # 2. enter
    # 3. picked element
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

    # real file in main folder
    if ! touch "$target_file" 2>/dev/null; then
        message_client "cannot create note: $target_file"
        debug_log "touch failed: target=$target_file session=$SESSION_NAME"
        exit 1
    fi

    # update symlink
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
CURRENT_CLIENT="$(tmux_format '#{client_name}')"
CURRENT_SESSION="$(tmux_format '#{session_name}')"

[ -n "$SOURCE_CLIENT" ] || SOURCE_CLIENT="$CURRENT_CLIENT"
[ -n "$SESSION_NAME" ] || SESSION_NAME="$CURRENT_SESSION"

HIDDEN_PREFIX="$(tmux_option "@jot-hidden-session-prefix" "__tmux__jot_")"

if [ "$MODE" = "main" ] && [[ "${CURRENT_SESSION:-$SESSION_NAME}" == "$HIDDEN_PREFIX"* ]]; then
    detach_current_client
    exit 0
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

DEBUG="$(tmux_option "@jot-debug" "off")"
LOG_FILE="$(expand_path "$(tmux_option "@jot-log-file" "$HOME/.local/state/tmux-jot.log")")"
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || printf '%s' "$0")"

if is_true "$DEBUG"; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
fi

debug_log "--- EXEC START --- mode=$MODE src_sess=$SESSION_NAME file=$FILE_PATH popup=$POPUP_SESSION"

case "$MODE" in
popup_picker)
    select_note
    prepare_selected_note

    schedule_editor_popup
    exit 0
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

main)
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
            message_client "cannot open editor popup"
            debug_log "CRITICAL: editor popup failed"
            exit 1
        fi
    else
        if tmux has-session -t "$POPUP_SESSION" 2>/dev/null; then
            tmux kill-session -t "$POPUP_SESSION" 2>/dev/null || true
        fi

        if ! display_picker_popup 2>/dev/null; then
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
