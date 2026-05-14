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

open_cleanup() {
    resolve_note_context
    display_cleanup_popup
}
