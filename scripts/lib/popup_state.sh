popup_state() {
    tmux show-option -gqv "$JOT_POPUP_STATE_KEY" 2>/dev/null || true
}

set_popup_state() {
    local token="$1"
    local kind="$2"
    local owner_pid="$3"

    tmux set-option -gq "$JOT_POPUP_STATE_KEY" "${token}|${kind}|${owner_pid}|${SOURCE_CLIENT}" 2>/dev/null || true
    debug_log "popup state set: client=$SOURCE_CLIENT kind=$kind token=$token pid=$owner_pid"
}

clear_popup_state() {
    tmux set-option -guq "$JOT_POPUP_STATE_KEY" 2>/dev/null || tmux set-option -gq "$JOT_POPUP_STATE_KEY" "" 2>/dev/null || true
}

clear_popup_state_if_token() {
    local token="$1"
    local state

    [ -n "$token" ] || return 0

    state="$(popup_state)"
    [ -n "$state" ] || return 0

    if [ "${state%%|*}" = "$token" ]; then
        debug_log "popup state clear: client=$SOURCE_CLIENT token=$token"
        clear_popup_state
    fi
}

cleanup_active_popup_state() {
    clear_popup_state_if_token "${ACTIVE_POPUP_TOKEN:-}"
}

begin_popup_lifecycle() {
    local kind="$1"
    local token

    token="${kind}:$$:${RANDOM:-0}"
    set_popup_state "$token" "$kind" "$$"
    ACTIVE_POPUP_TOKEN="$token"
    trap cleanup_active_popup_state EXIT
    trap 'exit 0' HUP INT TERM
}

popup_state_owner_pid() {
    local state="$1"
    local rest
    local owner_pid

    [ -n "$state" ] || return 1
    [[ "$state" == *"|"* ]] || return 1

    rest="${state#*|}"
    [[ "$rest" == *"|"* ]] || return 1

    rest="${rest#*|}"
    owner_pid="${rest%%|*}"
    case "$owner_pid" in
    "" | *[!0-9]*) return 1 ;;
    esac

    printf '%s' "$owner_pid"
}

popup_state_is_active() {
    local owner_pid

    owner_pid="$(popup_state_owner_pid "$1" 2>/dev/null || true)"
    [ -n "$owner_pid" ] || return 1
    kill -0 "$owner_pid" 2>/dev/null
}

popup_state_client() {
    local state="$1"
    local rest

    [ -n "$state" ] || return 1
    [[ "$state" == *"|"* ]] || return 1

    rest="${state#*|}"
    [[ "$rest" == *"|"* ]] || return 1

    rest="${rest#*|}"
    [[ "$rest" == *"|"* ]] || return 1

    printf '%s' "${rest#*|}"
}

popup_state_kind() {
    local state="$1"
    local rest

    [ -n "$state" ] || return 1
    [[ "$state" == *"|"* ]] || return 1

    rest="${state#*|}"
    printf '%s' "${rest%%|*}"
}

popup_client_from_option_key() {
    local option="$1"
    local safe
    local pts

    [[ "$option" == @jot_popup_* ]] || return 1
    safe="${option#@jot_popup_}"

    case "$safe" in
    _dev_pts_*)
        pts="${safe#_dev_pts_}"
        case "$pts" in
        "" | *[!0-9]*) return 1 ;;
        esac
        printf '/dev/pts/%s' "$pts"
        ;;
    *) return 1 ;;
    esac
}

active_popup_client_from_any_state() {
    local line
    local option
    local state
    local client

    while IFS= read -r line; do
        option="${line%% *}"
        [ "$option" != "$line" ] || continue
        [[ "$option" == @jot_popup_* ]] || continue

        state="${line#* }"
        if popup_state_is_active "$state"; then
            client="$(popup_state_client "$state" 2>/dev/null || true)"
            [ -n "$client" ] || client="$(popup_client_from_option_key "$option" 2>/dev/null || true)"
            if [ -n "$client" ]; then
                printf '%s' "$client"
                return 0
            fi
        fi
    done < <(tmux show-options -gq 2>/dev/null || true)

    return 1
}

jot_popup_is_open() {
    local state

    state="$(popup_state)"
    [ -n "$state" ] || return 1

    if popup_state_is_active "$state"; then
        return 0
    fi

    debug_log "stale popup state cleared: client=$SOURCE_CLIENT state=$state"
    clear_popup_state
    return 1
}

close_popup_if_present() {
    local client="${1:-$CURRENT_CLIENT}"

    if [ -n "$client" ]; then
        tmux display-popup -c "$client" -C 2>/dev/null
    else
        tmux display-popup -C 2>/dev/null
    fi
}

close_popup() {
    close_popup_if_present "$@" || true
}

toggle_popup_off_if_open() {
    if ! jot_popup_is_open; then
        return 1
    fi

    debug_log "toggle off: closing popup for client=$SOURCE_CLIENT"
    close_popup "$SOURCE_CLIENT"
    clear_popup_state
    return 0
}
