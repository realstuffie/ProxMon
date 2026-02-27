#!/bin/bash
set -euo pipefail

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

printf '%s\n' "Removing ProxMon AppArmor policy snippet..."

if [ -f "$SNIPPET_FILE" ]; then
  run_root rm -f "$SNIPPET_FILE"
  printf '%s\n' "Removed: $SNIPPET_FILE"
else
  printf '%s\n' "No snippet file found at: $SNIPPET_FILE"
fi

if [ -f "$DISPATCH_FILE" ]; then
  tmp_file="$(mktemp)"
  trap 'rm -f "$tmp_file"' EXIT
  grep -Fvx "$INCLUDE_LINE" "$DISPATCH_FILE" >"$tmp_file" || true
  run_root cp "$tmp_file" "$DISPATCH_FILE"
  run_root chmod 0644 "$DISPATCH_FILE"
  rm -f "$tmp_file"
  trap - EXIT
  printf '%s\n' "Removed include line from: $DISPATCH_FILE"
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