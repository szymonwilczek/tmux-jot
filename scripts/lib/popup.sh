popup_dimension_cells() {
    local dimension="$1"
    local total="$2"
    local number
    local cells

    case "$dimension" in
    *%)
        number="${dimension%\%}"
        number="$(normalize_unsigned_integer "$number" 2>/dev/null)" || number=50
        cells=$((total * number / 100))
        ;;
    "" | *[!0-9]*)
        cells=$((total / 2))
        ;;
    *)
        cells="$(normalize_unsigned_integer "$dimension" 2>/dev/null)" || cells=$((total / 2))
        ;;
    esac

    clamp_number "$cells" 1 "$total"
}

popup_anchor_position() {
    local position="$1"
    local dimension="$2"
    local total="$3"
    local available
    local number

    available=$((total - dimension))
    [ "$available" -ge 0 ] || available=0

    case "$position" in
    R)
        printf '%s' "$available"
        ;;
    C)
        printf '%s' "$((available / 2))"
        ;;
    *%)
        number="${position%\%}"
        number="$(normalize_unsigned_integer "$number" 2>/dev/null)" || number=0
        printf '%s' "$((available * number / 100))"
        ;;
    "" | *[!0-9]*)
        printf '%s' "$position"
        ;;
    *)
        printf '%s' "$position"
        ;;
    esac
}

popup_resolved_x() {
    local client_width
    local popup_width

    client_width="$(popup_client_width)"
    popup_width="$(popup_dimension_cells "$WIDTH" "$client_width")"
    popup_anchor_position "$POS_X" "$popup_width" "$client_width"
}

popup_resolved_y() {
    local client_height
    local popup_height

    client_height="$(popup_client_height)"
    popup_height="$(popup_dimension_cells "$HEIGHT" "$client_height")"
    popup_anchor_position "$POS_Y" "$popup_height" "$client_height"
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

    POS_X="$pos_x"
    POS_Y="$pos_y"
    WIDTH="$width"
    HEIGHT="$height"
    pos_x="$(popup_resolved_x)"
    pos_y="$(popup_resolved_y)"

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
    local icon="${2:-$TITLE_ICON}"

    template="${template//\{icon\}/$icon}"
    template="${template//\{session\}/$SESSION_NAME}"
    template="${template//\{note\}/${NOTE_NAME:-$SESSION_NAME}}"
    template="${template//\{file\}/$FILE_PATH}"
    printf '%s' "$template"
}

editor_title() {
    tmux_title "$(render_template "$TITLE_TEMPLATE" "$TITLE_ICON")"
}

fzf_prompt() {
    render_template "$FZF_PROMPT_TEMPLATE" "$PICKER_ICON"
}

content_search_prompt() {
    render_template "$CONTENT_SEARCH_PROMPT_TEMPLATE" "$CONTENT_SEARCH_ICON"
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

replace_popup_command() {
    local command="$1"

    if [ -n "$SOURCE_CLIENT" ]; then
        tmux display-popup -c "$SOURCE_CLIENT" -C \; run-shell -b "$command"
    else
        tmux display-popup -C \; run-shell -b "$command"
    fi
}

schedule_picker_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" open_picker "$SOURCE_CLIENT" "$SESSION_NAME")"
    debug_log "Scheduling async picker open: $command"
    replace_popup_command "$command"
}

schedule_content_search_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" open_content_search "$SOURCE_CLIENT" "$SESSION_NAME")"
    debug_log "Scheduling async content search open: $command"
    replace_popup_command "$command"
}

schedule_doctor_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" open_doctor "$SOURCE_CLIENT" "$SESSION_NAME")"
    debug_log "Scheduling async doctor open: $command"
    replace_popup_command "$command"
}

schedule_cleanup_popup() {
    local command

    command="$(shell_join "$SCRIPT_PATH" open_cleanup "$SOURCE_CLIENT" "$SESSION_NAME")"
    debug_log "Scheduling async cleanup open: $command"
    replace_popup_command "$command"
}

schedule_editor_popup() {
    local file="${1:-$FILE_PATH}"
    local note="${2:-$NOTE_NAME}"
    local command

    command="$(shell_join "$SCRIPT_PATH" open_editor "$SOURCE_CLIENT" "$SESSION_NAME" "$file" "$note")"
    debug_log "Scheduling async editor open: $command"
    replace_popup_command "$command"
}

wait_for_key() {
    printf '\nPress any key to close...'
    IFS= read -r -n 1 REPLY || true
    printf '\n'
}
