expand_path() {
    case "$1" in
    \~) printf '%s' "$HOME" ;;
    \~/*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    *) printf '%s' "$1" ;;
    esac
}

normalize_extension() {
    local ext="$1"

    ext="${ext#.}"
    ext="${ext//\//_}"
    [ -n "$ext" ] || ext="md"
    printf '%s' "$ext"
}

safe_name() {
    local input="$1"
    local safe

    safe="${input//[^A-Za-z0-9_-]/_}"
    [ -n "$safe" ] || safe="session"
    printf '%s' "$safe"
}

trim_space() {
    local value="$1"

    value="${value//$'\r'/}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

is_true() {
    case "${1:-}" in
    1 | on | true | yes | y) return 0 ;;
    *) return 1 ;;
    esac
}

shell_join() {
    local output=""
    local quoted
    local arg

    for arg in "$@"; do
        printf -v quoted '%q' "$arg"
        output="${output}${output:+ }${quoted}"
    done

    printf '%s' "$output"
}

tmux_title() {
    printf '%s' "${1//#/##}"
}

tmux_target_option() {
    local target="$1"
    local option="$2"
    local default_value="${3:-}"
    local value

    value="$(tmux show-option -t "$target" -qv "$option" 2>/dev/null || true)"
    if [ -n "$value" ]; then
        printf '%s' "$value"
    else
        printf '%s' "$default_value"
    fi
}

setup_debug_log() {
    local dir

    is_true "$DEBUG" || return 0

    dir="${LOG_FILE%/*}"
    [ "$dir" != "$LOG_FILE" ] || dir="."
    mkdir -p "$dir" 2>/dev/null || true
}

debug_log() {
    local message="$1"

    is_true "$DEBUG" || return 0
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >>"$LOG_FILE" 2>/dev/null || true
}

message_client() {
    local message="$1"

    if [ -n "${SOURCE_CLIENT:-}" ]; then
        tmux display-message -c "$SOURCE_CLIENT" "tmux-jot: $message" 2>/dev/null || true
    else
        tmux display-message "tmux-jot: $message" 2>/dev/null || true
    fi
}

has_note_file() {
    [ -n "${1:-}" ] && [ -e "$1" ]
}

note_name_is_valid() {
    local name="$1"

    [ -n "$name" ] || return 1
    [[ "$name" != *"/"* ]] || return 1
    [[ "$name" != *$'\n'* ]] || return 1
    [[ "$name" != *$'\r'* ]] || return 1
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

command_binary() {
    local command="$RG_COMMAND"

    if [ "$#" -gt 0 ]; then
        command="$1"
    fi
    command="${command%% *}"
    printf '%s' "$command"
}

wait_for_key() {
    printf '\nPress any key to close...'
    IFS= read -r -n 1 REPLY || true
    printf '\n'
}
