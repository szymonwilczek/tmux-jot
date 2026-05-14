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
