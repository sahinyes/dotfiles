#!/usr/bin/env bash
# tmux status bar helper — usage: status.sh <segment> [pane id, for git]
# Works on macOS and Linux (BSD and GNU tools, bash 3.2). A segment whose
# tools are missing prints nothing, so the status bar never shows an error.
set -euo pipefail

have() { command -v "$1" >/dev/null 2>&1; }

ncpu() { getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1; }

# Linux: busy share of all CPUs over half a second, from /proc/stat.
# (Linux `ps %cpu` is a lifetime average per process, so it would mislead.)
linux_cpu() {
    local u1 n1 s1 i1 w1 q1 sq1 st1 u2 n2 s2 i2 w2 q2 sq2 st2 busy total
    read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ </proc/stat
    sleep 0.5
    read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ </proc/stat
    busy=$(((u2 + n2 + s2 + q2 + sq2 + st2) - (u1 + n1 + s1 + q1 + sq1 + st1)))
    total=$((busy + (i2 + w2) - (i1 + w1)))
    [ "$total" -gt 0 ] || total=1
    printf '%d%%' $((busy * 100 / total))
}

case "${1:-}" in
cpu)
    if [ -r /proc/stat ]; then
        linux_cpu
    else
        ps -A -o %cpu | awk -v n="$(ncpu)" '{s+=$1} END {printf "%.0f%%", s/n}'
    fi
    ;;
ram)
    if [ -r /proc/meminfo ]; then
        awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {if (t) printf "%d%%", (t-a)*100/t}' /proc/meminfo
    elif have memory_pressure; then
        memory_pressure 2>/dev/null | awk '/percentage/{printf "%d%%", 100-$5}'
    fi
    ;;
net)
    if have networksetup; then
        # macOS: WiFi SSID + connection type
        wifi_dev=$(networksetup -listallhardwareports 2>/dev/null | grep -A1 "Wi-Fi" | awk '/Device/{print $2}' || true)
        ssid=""
        [ -n "$wifi_dev" ] && ssid=$(networksetup -getairportnetwork "$wifi_dev" 2>/dev/null | sed 's/.*: //' || true)
        iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' || true)
        if [ -z "$iface" ]; then
            echo " down"
        elif [ -n "$ssid" ] && [ "$ssid" != "You are not associated with an AirPort network." ]; then
            echo " $ssid"
        else
            case "$iface" in
            en*) echo "󰈀 ethernet" ;;
            *utun*)
                tsip=""
                have tailscale && tsip=$(tailscale ip -4 2>/dev/null | head -n 1 || true)
                echo "󰖂 ${tsip:-tailscale}"
                ;;
            *) echo "󰈀 $iface" ;;
            esac
        fi
    elif have ip; then
        # Linux: interface of the default route, named after its
        # NetworkManager connection (the SSID on WiFi) when nmcli exists.
        iface=$(ip route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") {print $(i+1); exit}}' || true)
        name=""
        if [ -n "$iface" ] && have nmcli; then
            name=$(nmcli -t -f DEVICE,CONNECTION device status 2>/dev/null | awk -F: -v d="$iface" '$1 == d {print $2; exit}' || true)
        fi
        case "$iface" in
        '') echo " down" ;;
        wl*) echo " ${name:-$iface}" ;;
        tailscale* | tun* | wg*) echo "󰖂 $iface" ;;
        *) echo "󰈀 ${name:-$iface}" ;;
        esac
    fi
    ;;
ip)
    if have tailscale; then
        tsip=$(tailscale ip -4 2>/dev/null | head -n 1 || true)
        echo "${tsip:-no-ts}"
    fi
    ;;
uptime)
    uptime | sed 's/.*up *//' | sed 's/,.*//' | xargs
    ;;
git)
    # $2 is the pane id from tmux.conf (#{pane_id}): each client shows the
    # branch of its own active pane. Without it nothing is printed.
    dir=""
    if [ -n "${2:-}" ]; then
        dir=$(tmux display-message -p -t "$2" -F '#{pane_current_path}' 2>/dev/null || true)
    fi
    if [ -n "$dir" ] && cd "$dir" 2>/dev/null; then
        # The pane may sit in a cloned target repo: never let its .git/config
        # run an fsmonitor hook (branch --show-current does not read the
        # index today; this keeps it that way).
        branch=$(git -c core.fsmonitor=false branch --show-current 2>/dev/null || true)
        if [ -n "$branch" ]; then echo " $branch"; fi
    fi
    ;;
claude)
    # Claude usage bars; prints nothing unless the claude-pulse cache is fresh.
    script="$(dirname "$0")/claude-pulse-tmux.py"
    if have python3 && [ -f "$script" ]; then
        python3 "$script" 2>/dev/null || true
    fi
    ;;
esac
