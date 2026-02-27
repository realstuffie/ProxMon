#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC_FILE="$REPO_ROOT/apparmor/plasmashell.local"
LOCAL_DIR="/etc/apparmor.d/local"
SNIPPET_FILE="$LOCAL_DIR/plasmashell-proxmon"
DISPATCH_FILE="$LOCAL_DIR/plasmashell"
INCLUDE_LINE="#include <local/plasmashell-proxmon>"

run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v doas >/dev/null 2>&1; then
    doas "$@"
  else
    su -c "$(printf '%q ' "$@")"
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "Missing required command: $1" >&2
    exit 1
  fi
}

if [ ! -f "$SRC_FILE" ]; then
  printf '%s\n' "Missing source policy file: $SRC_FILE" >&2
  exit 1
fi

require_cmd install
require_cmd cp
require_cmd grep
require_cmd touch
require_cmd printf

printf '%s\n' "Installing ProxMon AppArmor policy snippet..."
run_root install -d -m 0755 "$LOCAL_DIR"
run_root cp "$SRC_FILE" "$SNIPPET_FILE"
run_root chmod 0644 "$SNIPPET_FILE"

printf '%s\n' "Ensuring dispatcher include exists in $DISPATCH_FILE..."
run_root touch "$DISPATCH_FILE"
if ! run_root grep -Fqx "$INCLUDE_LINE" "$DISPATCH_FILE"; then
  run_root sh -c "printf '%s\n' '$INCLUDE_LINE' >> '$DISPATCH_FILE'"
fi

if command -v apparmor_parser >/dev/null 2>&1; then
  printf '%s\n' "Reloading AppArmor profile: /etc/apparmor.d/usr.bin.plasmashell"
  run_root apparmor_parser -r /etc/apparmor.d/usr.bin.plasmashell || true
elif command -v systemctl >/dev/null 2>&1; then
  printf '%s\n' "apparmor_parser not found, attempting service reload..."
  run_root systemctl reload apparmor 2>/dev/null || run_root systemctl restart apparmor 2>/dev/null || true
fi

printf '\n'
printf '%s\n' "Done."
printf '%s\n' "Snippet installed at: $SNIPPET_FILE"
printf '%s\n' "Include ensured in: $DISPATCH_FILE"