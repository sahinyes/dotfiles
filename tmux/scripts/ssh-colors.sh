#!/usr/bin/env bash
# SSH wrapper: changes tmux pane colors based on target host
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
    local host=""
    # Extract hostname from ssh args (skip flags and their values)
    local skip_next=false
    for arg in "$@"; do
        if $skip_next; then skip_next=false; continue; fi
        case "$arg" in
            -*) # flags that take a value
                case "$arg" in
                    -[bcDEeFIiJLlmOopQRSWw]) skip_next=true ;;
                esac
                ;;
            *)
                # First non-flag arg is [user@]host
                host="${arg##*@}"
                break
                ;;
        esac
    done

    # Set tmux status bar + window name based on host
    if [ -n "$TMUX" ] && [ -n "$host" ]; then
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

        tmux set status-style "bg=#2E3440,fg=$color"
        tmux set status-left "#[bg=$color,fg=#2E3440,bold] $icon $label #[bg=#2E3440,fg=$color]"
        tmux setw automatic-rename off
        tmux rename-window "$label"
        # Color this window tab
        tmux setw window-status-style "bg=$color,fg=#2E3440"
        tmux setw window-status-current-style "bg=$color,fg=#2E3440,bold"
    fi

    # Run actual ssh
    command ssh "$@"
    local exit_code=$?

    # Reset status bar + window style on disconnect
    if [ -n "$TMUX" ]; then
        tmux setw window-status-style 'bg=#3B4252,fg=#D8DEE9'
        tmux setw window-status-current-style 'bg=#81A1C1,fg=#2E3440,bold'
        tmux set status-style 'bg=#2E3440,fg=#D8DEE9'
        tmux setw automatic-rename on
        tmux source-file ~/.tmux.conf 2>/dev/null
    fi

    return $exit_code
}
