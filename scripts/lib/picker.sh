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

    if [ -z "$fzf_out" ]; then
        debug_log "picker cancelled: empty output status=$fzf_status session=$SESSION_NAME"
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

    # fzf returns status 1 when there is no match, but with --print-query we can still
    # get a valid query to create a new note from.
    if [ "$fzf_status" -ne 0 ] && [ "$fzf_status" -ne 1 ]; then
        debug_log "picker cancelled: unsupported status=$fzf_status session=$SESSION_NAME"
        exit 0
    fi
    if [ -z "$selection" ] && [ -z "$query" ]; then
        debug_log "picker cancelled: no selection and empty query status=$fzf_status session=$SESSION_NAME"
        exit 0
    fi

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
