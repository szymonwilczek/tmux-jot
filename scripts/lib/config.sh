load_context_and_config() {
    local out
    local format

    format="#{client_name}${SEP}#{session_name}${SEP}#{@jot-hidden-session-prefix}${SEP}#{@jot-debug}${SEP}#{@jot-icons}${SEP}#{@jot-log-file}${SEP}#{@jot-dir}${SEP}#{@jot-extension}${SEP}#{@jot-session-dir}${SEP}#{@jot-editor}${SEP}#{@jot-shell}${SEP}#{@jot-fzf-command}${SEP}#{@jot-fzf-options}${SEP}#{@jot-sort-notes}${SEP}#{@jot-rg-command}${SEP}#{@jot-content-search-prompt}${SEP}#{@jot-content-search-preview-window}${SEP}#{@jot-border-color}${SEP}#{@jot-border-style}${SEP}#{@jot-popup-width}${SEP}#{@jot-popup-height}${SEP}#{@jot-popup-x}${SEP}#{@jot-popup-y}${SEP}#{@jot-title-icon}${SEP}#{@jot-title}${SEP}#{@jot-fzf-prompt}"
    out="$(tmux display-message -p "$format" 2>/dev/null || true)"

    IFS="$SEP" read -r \
        TMUX_CLIENT TMUX_SESSION CFG_HIDDEN_PREFIX CFG_DEBUG CFG_ICONS CFG_LOG_FILE \
        CFG_JOT_DIR CFG_EXT CFG_SESSION_DIR CFG_EDITOR CFG_SHELL \
        CFG_FZF_COMMAND CFG_FZF_OPTIONS CFG_SORT_NOTES CFG_RG_COMMAND \
        CFG_CONTENT_SEARCH_PROMPT CFG_CONTENT_SEARCH_PREVIEW_WINDOW \
        CFG_BORDER_COLOR CFG_BORDER_STYLE CFG_POPUP_WIDTH CFG_POPUP_HEIGHT CFG_POPUP_X CFG_POPUP_Y \
        CFG_ICON CFG_TITLE CFG_FZF_PROMPT <<<"$out"

    CURRENT_CLIENT="${RAW_SOURCE_CLIENT:-$TMUX_CLIENT}"
    CURRENT_SESSION="${RAW_SESSION_NAME:-$TMUX_SESSION}"
    SOURCE_CLIENT="$CURRENT_CLIENT"
    SESSION_NAME="$CURRENT_SESSION"

    HIDDEN_PREFIX="${CFG_HIDDEN_PREFIX:-__tmux__jot_}"
    DEBUG="${CFG_DEBUG:-off}"
    ICONS="${CFG_ICONS:-on}"
    LOG_FILE="$(expand_path "${CFG_LOG_FILE:-$HOME/.local/state/tmux-jot.log}")"

    JOT_DIR_RAW="${CFG_JOT_DIR:-$HOME/.local/share/tmux-jot}"
    EXT_RAW="${CFG_EXT:-md}"
    EXT="$(normalize_extension "$EXT_RAW")"
    SESSION_DIR_RAW="${CFG_SESSION_DIR:-}"

    EDITOR_COMMAND="${CFG_EDITOR:-${EDITOR:-nvim}}"
    COMMAND_SHELL="${CFG_SHELL:-/bin/bash}"
    FZF_COMMAND="${CFG_FZF_COMMAND:-fzf}"
    FZF_OPTIONS="${CFG_FZF_OPTIONS:-}"
    SORT_NOTES="${CFG_SORT_NOTES:-off}"
    RG_COMMAND="${CFG_RG_COMMAND:-rg}"
    CONTENT_SEARCH_PREVIEW_WINDOW="${CFG_CONTENT_SEARCH_PREVIEW_WINDOW:-right,60%,border-left}"

    BORDER_COLOR="${CFG_BORDER_COLOR:-#b38d59}"
    BORDER_STYLE="${CFG_BORDER_STYLE:-rounded}"
    WIDTH="${CFG_POPUP_WIDTH:-40%}"
    HEIGHT="${CFG_POPUP_HEIGHT:-50%}"
    POPUP_WIDTH_BASE="$WIDTH"
    POPUP_HEIGHT_BASE="$HEIGHT"
    POS_X="${CFG_POPUP_X:-R}"
    POS_Y="${CFG_POPUP_Y:-0}"

    TITLE_ICON="${CFG_ICON:-📌}"
    PICKER_ICON="📝"
    CONTENT_SEARCH_ICON="🔎"
    if ! is_true "$ICONS"; then
        TITLE_ICON=""
        PICKER_ICON=""
        CONTENT_SEARCH_ICON=""
    fi
    if [ -n "$CFG_TITLE" ]; then
        TITLE_TEMPLATE="$CFG_TITLE"
    else
        TITLE_TEMPLATE=' {icon} {note} '
    fi
    if [ -n "$CFG_FZF_PROMPT" ]; then
        FZF_PROMPT_TEMPLATE="$CFG_FZF_PROMPT"
    else
        FZF_PROMPT_TEMPLATE='{icon} Select / Create: '
    fi
    if [ -n "$CFG_CONTENT_SEARCH_PROMPT" ]; then
        CONTENT_SEARCH_PROMPT_TEMPLATE="$CFG_CONTENT_SEARCH_PROMPT"
    else
        CONTENT_SEARCH_PROMPT_TEMPLATE='{icon} Search content: '
    fi

    if [ "$POS_X" = "r" ]; then
        POS_X="R"
    fi
}
