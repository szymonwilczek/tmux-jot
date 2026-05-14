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

render_template() {
    local template="$1"

    template="${template//\{icon\}/$ICON}"
    template="${template//\{session\}/$SESSION_NAME}"
    template="${template//\{note\}/${NOTE_NAME:-$SESSION_NAME}}"
    template="${template//\{file\}/$FILE_PATH}"
    printf '%s' "$template"
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

wait_for_key() {
    printf '\nPress any key to close...'
    IFS= read -r -n 1 REPLY || true
    printf '\n'
}
