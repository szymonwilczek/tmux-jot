#!/usr/bin/env bash

CURRENT_SESSION=$(tmux display-message -p '#S')

if [[ "$CURRENT_SESSION" == __tmux__jot_* ]]; then
    tmux detach-client
    exit 0
fi

SESSION_NAME="$CURRENT_SESSION"
SAFE_SESSION=$(echo "$SESSION_NAME" | sed 's/[^a-zA-Z0-9_-]/_/g')
POPUP_SESSION="__tmux__jot_${SAFE_SESSION}"

# CONFIGURATION
JOT_DIR=$(tmux show-option -gqv "@jot-dir")
[ -z "$JOT_DIR" ] && JOT_DIR="$HOME/.local/share/tmux-jot"
mkdir -p "$JOT_DIR"

EXT=$(tmux show-option -gqv "@jot-extension")
[ -z "$EXT" ] && EXT="md"

FILE_PATH="$JOT_DIR/${SAFE_SESSION}.${EXT}"

EDITOR=$(tmux show-option -gqv "@jot-editor")
[ -z "$EDITOR" ] && EDITOR="${EDITOR:-nvim}"

BORDER_COLOR=$(tmux show-option -gqv "@jot-border-color")
[ -z "$BORDER_COLOR" ] && BORDER_COLOR="#b38d59"

BORDER_STYLE=$(tmux show-option -gqv "@jot-border-style")
[ -z "$BORDER_STYLE" ] && BORDER_STYLE="rounded"

WIDTH=$(tmux show-option -gqv "@jot-popup-width")
[ -z "$WIDTH" ] && WIDTH="40%"

HEIGHT=$(tmux show-option -gqv "@jot-popup-height")
[ -z "$HEIGHT" ] && HEIGHT="50%"

POS_X=$(tmux show-option -gqv "@jot-popup-x")
[ -z "$POS_X" ] && POS_X="100%"
if [ "$POS_X" == "R" ] || [ "$POS_X" == "r" ]; then
    POS_X="100%"
fi

POS_Y=$(tmux show-option -gqv "@jot-popup-y")
[ -z "$POS_Y" ] && POS_Y="0"

ICON=$(tmux show-option -gqv "@jot-title-icon")
[ -z "$ICON" ] && ICON="📝"

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

# PICKER
if [ "$1" == "internal_picker" ]; then
    SELECTED=$(ls -1 "$JOT_DIR" 2>/dev/null | grep "\.${EXT}$" | sed "s/\.${EXT}$//" | fzf --prompt="$ICON Wybierz / Utwórz: " --print-query | tail -n 1)

    if [ -n "$SELECTED" ]; then
        TARGET_FILE="$JOT_DIR/${SELECTED}.${EXT}"
        touch "$TARGET_FILE"

        if [ "$TARGET_FILE" != "$FILE_PATH" ]; then
            ln -sf "$TARGET_FILE" "$FILE_PATH"
        fi

        tmux detach-client
        tmux run-shell -b "tmux display-popup -b \"$BORDER_STYLE\" -S \"fg=$BORDER_COLOR\" -w \"$WIDTH\" -h \"$HEIGHT\" -x \"$POS_X\" -y \"$POS_Y\" -T \" $ICON $SESSION_NAME \" -E \"tmux attach-session -t '$POPUP_SESSION'\""
        exec $EDITOR "$FILE_PATH"
    fi

    tmux detach-client
    exit 0
fi

# TOGGLE ON
if [ "$1" == "main" ]; then
    if [ -e "$FILE_PATH" ]; then
        # EDITOR MODE: file exists
        if ! tmux has-session -t "$POPUP_SESSION" 2>/dev/null; then
            tmux new-session -d -s "$POPUP_SESSION" "$EDITOR '$FILE_PATH'"
            tmux set-option -t "$POPUP_SESSION" detach-on-destroy on
            tmux set-option -t "$POPUP_SESSION" status off
        fi
        # anchor
        tmux display-popup -b "$BORDER_STYLE" -S "fg=$BORDER_COLOR" -w "$WIDTH" -h "$HEIGHT" -x "$POS_X" -y "$POS_Y" -T " $ICON $SESSION_NAME " -E "tmux attach-session -t '$POPUP_SESSION'"
    else
        # PICKER MODE: no file
        if tmux has-session -t "$POPUP_SESSION" 2>/dev/null; then
            tmux kill-session -t "$POPUP_SESSION"
        fi
        tmux new-session -d -s "$POPUP_SESSION" "$SCRIPT_PATH internal_picker"
        tmux set-option -t "$POPUP_SESSION" detach-on-destroy on
        tmux set-option -t "$POPUP_SESSION" status off
        tmux display-popup -b "$BORDER_STYLE" -S "fg=$BORDER_COLOR" -w 50% -h 50% -x C -y C -T " tmux-jot " -E "tmux attach-session -t '$POPUP_SESSION'"
    fi
    exit 0
fi
