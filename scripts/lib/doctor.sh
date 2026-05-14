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
    printf '  %-18s %s\n' "size delta" "$POPUP_SIZE_DELTA"
    printf '  %-18s %s,%s\n' "popup pos" "$POS_X" "$POS_Y"
    printf '\n'

    printf 'Hidden sessions\n'
    doctor_hidden_sessions
    printf '\n'

    printf 'Popup states\n'
    doctor_popup_states
}

open_doctor() {
    resolve_note_context
    display_doctor_popup
}
