popup_size_delta_option() {
    printf '%s' "@jot-size-delta"
}

normalize_integer() {
    local value="$1"
    local sign=1
    local digits

    [[ "$value" =~ ^-?[0-9]+$ ]] || {
        printf '0'
        return 0
    }

    if [[ "$value" == -* ]]; then
        sign=-1
        digits="${value#-}"
    else
        digits="$value"
    fi

    printf '%s' $((sign * 10#$digits))
}

normalize_unsigned_integer() {
    local value="$1"

    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    printf '%s' $((10#$value))
}

clamp_number() {
    local value="$1"
    local min="$2"
    local max="$3"

    if [ "$value" -lt "$min" ]; then
        value="$min"
    elif [ "$value" -gt "$max" ]; then
        value="$max"
    fi

    printf '%s' "$value"
}

popup_client_dimension() {
    local format="$1"
    local fallback="$2"
    local value

    value="$(tmux display-message -c "$SOURCE_CLIENT" -p "$format" 2>/dev/null || true)"
    value="$(normalize_unsigned_integer "$value" 2>/dev/null)" || value="$fallback"
    if [ -z "$value" ] || [ "$value" -le 0 ]; then
        value="$fallback"
    fi

    printf '%s' "$value"
}

popup_client_width() {
    popup_client_dimension '#{client_width}' 9999
}

popup_client_height() {
    popup_client_dimension '#{client_height}' 9999
}

session_popup_size_delta() {
    local value

    value="$(tmux show-option -t "$SESSION_NAME" -qv "$(popup_size_delta_option)" 2>/dev/null || true)"
    normalize_integer "$value"
}

set_session_popup_size_delta() {
    local delta="$1"

    tmux set-option -t "$SESSION_NAME" -q "$(popup_size_delta_option)" "$(normalize_integer "$delta")" 2>/dev/null || true
}

popup_dimension_with_delta() {
    local dimension="$1"
    local delta="$2"
    local max_cells="${3:-9999}"
    local number
    local adjusted

    max_cells="$(normalize_unsigned_integer "$max_cells" 2>/dev/null)" || max_cells=9999
    [ "$max_cells" -gt 0 ] || max_cells=9999

    case "$dimension" in
    *%)
        number="${dimension%\%}"
        number="$(normalize_unsigned_integer "$number" 2>/dev/null)" || {
            printf '%s' "$dimension"
            return 0
        }

        adjusted="$(clamp_number "$((number + delta))" 20 100)"
        printf '%s%%' "$adjusted"
        ;;
    "" | *[!0-9]*)
        printf '%s' "$dimension"
        ;;
    *)
        number="$(normalize_unsigned_integer "$dimension" 2>/dev/null)" || {
            printf '%s' "$dimension"
            return 0
        }

        adjusted="$(clamp_number "$((number + delta))" 10 "$max_cells")"
        printf '%s' "$adjusted"
        ;;
    esac
}

popup_width_with_delta() {
    popup_dimension_with_delta "$POPUP_WIDTH_BASE" "$1" "$(popup_client_width)"
}

popup_height_with_delta() {
    popup_dimension_with_delta "$POPUP_HEIGHT_BASE" "$1" "$(popup_client_height)"
}

apply_session_popup_size() {
    POPUP_SIZE_DELTA="$(session_popup_size_delta)"
    WIDTH="$(popup_width_with_delta "$POPUP_SIZE_DELTA")"
    HEIGHT="$(popup_height_with_delta "$POPUP_SIZE_DELTA")"
}

schedule_popup_kind() {
    local kind="$1"

    case "$kind" in
    picker)
        schedule_picker_popup
        ;;
    content_search)
        schedule_content_search_popup
        ;;
    doctor)
        schedule_doctor_popup
        ;;
    cleanup)
        schedule_cleanup_popup
        ;;
    editor)
        resolve_note_context
        if has_note_file "$FILE_PATH"; then
            schedule_editor_popup "$FILE_PATH" "$NOTE_NAME"
        else
            schedule_picker_popup
        fi
        ;;
    esac
}

reload_active_popup() {
    local state
    local kind

    state="$(popup_state)"
    if ! popup_state_is_active "$state"; then
        [ -z "$state" ] || clear_popup_state
        return 0
    fi

    kind="$(popup_state_kind "$state" 2>/dev/null || true)"
    [ -n "$kind" ] || return 0

    close_popup "$SOURCE_CLIENT"
    schedule_popup_kind "$kind"
}

resize_popup() {
    local direction="$1"
    local step
    local current_delta
    local next_delta
    local current_width
    local current_height
    local next_width
    local next_height

    case "$direction" in
    increase) step=5 ;;
    decrease) step=-5 ;;
    *)
        message_client "unknown resize direction: $direction"
        exit 2
        ;;
    esac

    current_delta="$(session_popup_size_delta)"
    next_delta=$((current_delta + step))
    current_width="$(popup_width_with_delta "$current_delta")"
    current_height="$(popup_height_with_delta "$current_delta")"
    next_width="$(popup_width_with_delta "$next_delta")"
    next_height="$(popup_height_with_delta "$next_delta")"

    if [ "$next_width" = "$current_width" ] && [ "$next_height" = "$current_height" ]; then
        return 0
    fi

    set_session_popup_size_delta "$next_delta"
    apply_session_popup_size

    debug_log "popup resize: session=$SESSION_NAME direction=$direction delta=$POPUP_SIZE_DELTA size=$WIDTH x $HEIGHT"
    message_client "popup size: $WIDTH x $HEIGHT"

    reload_active_popup
}

reset_popup_size() {
    local current_delta

    current_delta="$(session_popup_size_delta)"
    if [ "$current_delta" -eq 0 ]; then
        return 0
    fi

    set_session_popup_size_delta 0
    apply_session_popup_size

    debug_log "popup resize reset: session=$SESSION_NAME size=$WIDTH x $HEIGHT"
    message_client "popup size: $WIDTH x $HEIGHT"

    reload_active_popup
}
