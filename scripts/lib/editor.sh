popup_editor_command() {
    shell_join "$SCRIPT_PATH" popup_editor "$SOURCE_CLIENT" "$SESSION_NAME" "$POPUP_SESSION"
}

display_editor_popup() {
    display_popup "$SOURCE_CLIENT" "$WIDTH" "$HEIGHT" "$POS_X" "$POS_Y" "$(editor_title)" "$(popup_editor_command)"
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
