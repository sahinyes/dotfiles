#!/usr/bin/env bash
# SSH wrapper: labels and colors the tmux status bar and window tab by host
# Source this file in .zshrc (or .bashrc):  . ~/.tmux/scripts/ssh-colors.sh
# It is sourced into your interactive shell, so it sets no shell options.
#
# Host names and IPs stay out of this public repo. Map them to a label in
# ~/.config/dotfiles/ssh-hosts (machine-local), one "host label" per line:
#   # host (glob allowed)   label
#   my-prod-box             prod
#   192.0.2.10              prod
#   *oob*                   oob
# Labels with their own color: dev prod gpu oob mac. Any other host keeps
# its own name and gets purple.

# Print the label for host $1: first matching line of the map, else the host.
_ssh_colors_label() {
    local host="$1" map="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/ssh-hosts" pat label
    # zsh treats an unquoted $pat in `case` as literal text unless GLOB_SUBST
    # is on; localoptions restores the user's options when we return.
    if [ -n "${ZSH_VERSION:-}" ]; then setopt localoptions globsubst; fi
    if [ -r "$map" ]; then
        while read -r pat label _; do
            case "$pat" in '' | '#'*) continue ;; esac
            # shellcheck disable=SC2254 # $pat is meant to match as a glob
            case "$host" in
            $pat)
                printf '%s\n' "${label:-$host}"
                return 0
                ;;
            esac
        done <"$map"
    fi
    printf '%s\n' "$host"
}

ssh() {
    local host="" arg skip_next=false
    # ssh options that take a value (-p 2222, -l root, ...). They may come
    # at the end of a cluster (-vp 2222, -Ap 2222); -p2222 or -lroot carry
    # the value in the same argument.
    local takes_value='^-[46AaCfGgKkMNnqsTtVvXxYy]*[BbcDEeFIiJLlmOoPpQRSWw]$'
    # The host is the first argument that is not an option or its value.
    for arg in "$@"; do
        if $skip_next; then skip_next=false; continue; fi
        case "$arg" in
            -*)
                if [[ "$arg" =~ $takes_value ]]; then skip_next=true; fi
                ;;
            *)
                # First non-flag arg is [user@]host
                host="${arg##*@}"
                break
                ;;
        esac
    done

    # Mark the pane that runs ssh, not the window you happen to look at
    # ($TMUX_PANE, so every tmux command below needs -t). tmux.conf's
    # status-left shows @ssh_label of the active pane; this pane's window
    # tab gets the color and the label as its name.
    local pane=""
    if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] && [ -n "$host" ]; then
        pane="$TMUX_PANE"
        local label color icon
        label="$(_ssh_colors_label "$host")"
        # The label ends up in a tmux format, where "#(...)" would run a
        # command: show only plain host-name characters.
        case "$label" in *[!A-Za-z0-9._:-]*) label="ssh" ;; esac
        case "$label" in
            dev)  color="#81A1C1"; icon="" ;;
            prod) color="#BF616A"; icon="" ;;
            gpu)  color="#A3BE8C"; icon="󰢮" ;;
            oob)  color="#EBCB8B"; icon="" ;;
            mac)  color="#88C0D0"; icon="" ;;
            *)    color="#B48EAD"; icon="" ;;
        esac

        tmux set -p -t "$pane" @ssh_label "$icon $label" \; \
            set -p -t "$pane" @ssh_color "$color" \; \
            set -w -t "$pane" automatic-rename off \; \
            set -w -t "$pane" window-status-style "bg=$color,fg=#2E3440" \; \
            set -w -t "$pane" window-status-current-style "bg=$color,fg=#2E3440,bold" \; \
            rename-window -t "$pane" "$label"
    fi

    # Run actual ssh
    command ssh "$@"
    local exit_code=$?

    # On disconnect remove exactly those settings from this pane and its
    # window; tmux.conf's values show through again.
    if [ -n "$pane" ]; then
        tmux set -pu -t "$pane" @ssh_label \; \
            set -pu -t "$pane" @ssh_color \; \
            set -wu -t "$pane" automatic-rename \; \
            set -wu -t "$pane" window-status-style \; \
            set -wu -t "$pane" window-status-current-style
    fi

    return $exit_code
}
