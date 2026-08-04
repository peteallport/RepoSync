#!/bin/bash

set -euo pipefail

LABEL="io.github.peteallport.reposync"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
BIN_DIR="$HOME/.local/bin"
LIBEXEC_DIR="$HOME/.local/libexec"
CONFIG_DIR="$HOME/.config/reposync"
STATE_DIR="$HOME/.local/state/reposync"
LOG_DIR="$HOME/Library/Logs/RepoSync"
AGENT_DIR="$HOME/Library/LaunchAgents"
WORKER="$LIBEXEC_DIR/reposync-worker"
PLIST="$AGENT_DIR/$LABEL.plist"
SERVICE_TARGET="gui/$(id -u)/$LABEL"

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

sed_replacement_escape() {
    sed -e 's/[\\&|]/\\&/g'
}

mkdir -p "$BIN_DIR" "$LIBEXEC_DIR" "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR" "$AGENT_DIR"
touch "$CONFIG_DIR/repos" "$LOG_DIR/reposync.log" "$LOG_DIR/launchd.out.log" "$LOG_DIR/launchd.err.log"

install -m 0755 "$SCRIPT_DIR/bin/reposync" "$BIN_DIR/reposync"
install -m 0755 "$SCRIPT_DIR/libexec/reposync-worker" "$WORKER"

escaped_worker=$(xml_escape "$WORKER" | sed_replacement_escape)
escaped_home=$(xml_escape "$HOME" | sed_replacement_escape)
escaped_stdout=$(xml_escape "$LOG_DIR/launchd.out.log" | sed_replacement_escape)
escaped_stderr=$(xml_escape "$LOG_DIR/launchd.err.log" | sed_replacement_escape)
temp_plist=$(mktemp "$AGENT_DIR/$LABEL.XXXXXX")

sed \
    -e "s|__WORKER__|$escaped_worker|g" \
    -e "s|__HOME__|$escaped_home|g" \
    -e "s|__STDOUT__|$escaped_stdout|g" \
    -e "s|__STDERR__|$escaped_stderr|g" \
    "$SCRIPT_DIR/share/$LABEL.plist.in" > "$temp_plist"

plutil -lint "$temp_plist" >/dev/null
chmod 0644 "$temp_plist"
mv "$temp_plist" "$PLIST"
rm -f "$STATE_DIR/paused"

if [ "${REPOSYNC_SKIP_LAUNCHCTL:-0}" != "1" ]; then
    launchctl enable "$SERVICE_TARGET" >/dev/null 2>&1 || true
    if launchctl print "$SERVICE_TARGET" >/dev/null 2>&1; then
        launchctl bootout "$SERVICE_TARGET" >/dev/null
    fi
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    launchctl kickstart "$SERVICE_TARGET"
fi

echo "RepoSync installed."
echo "CLI: $BIN_DIR/reposync"
echo "Config: $CONFIG_DIR/repos"
echo
echo "Add a repository with:"
echo "  reposync add /path/to/repository"
