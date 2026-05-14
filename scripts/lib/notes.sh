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

link_selected_note() {
    if ! ln -sfn "$FILE_PATH" "$SESSION_LINK" 2>/dev/null; then
        message_client "cannot link session note: $SESSION_LINK -> $FILE_PATH"
        debug_log "link failed: source=$FILE_PATH target=$SESSION_LINK session=$SESSION_NAME"
        exit 1
    fi
}
