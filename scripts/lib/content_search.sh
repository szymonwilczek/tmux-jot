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

open_content_search() {
    resolve_note_context
    display_content_search_popup
}
