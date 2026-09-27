#!/bin/bash
# Runs the terminal specs on Debian in Docker as a non-root user, with the
# repo mounted read-only. Mirrors the x86_64 work laptop (GNOME Terminal).
# Usage: bash tests/terminal/linux-docker.sh [debian:13|debian:12]
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
base="${1:-debian:13}"
case "$base" in
debian:12 | debian:13) ;;
*)
    echo "linux-docker: base image must be debian:12 or debian:13" >&2
    exit 2
    ;;
esac
image="dotfiles-terminal-test:${base#debian:}"

# gnome-terminal brings the schemas; dconf-cli and dbus make gsettings real.
docker build --platform linux/amd64 -t "$image" - <<EOF
FROM $base
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      gnome-terminal dconf-cli dbus dbus-user-session dconf-gsettings-backend libglib2.0-bin \
      fontconfig tmux git ncurses-bin bsdutils procps iproute2 \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash tester
USER tester
WORKDIR /home/tester
EOF

# Every spec runs even if an earlier one fails; the exit status reports any.
docker run --rm --platform linux/amd64 -v "$repo:/repo:ro" "$image" bash -c '
    cd /repo || exit 1
    rc=0
    for spec in gnome_terminal_spec tmux_spec doctor_spec; do
        bash "tests/terminal/$spec.sh" || rc=1
    done
    bash scripts/terminfo-mac.sh || rc=1
    bash scripts/doctor.sh || rc=1
    exit "$rc"
'
