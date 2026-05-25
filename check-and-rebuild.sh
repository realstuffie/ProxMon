#!/bin/bash
set -euo pipefail

PLASMOID_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/org.kde.plasma.proxmox"
LOG_FILE="$PLASMOID_DIR/rebuild.log"
FINGERPRINT_FILE="$PLASMOID_DIR/.build_fingerprint"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install.sh"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

notify_error() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send --urgency=critical \
      --icon=dialog-error \
      "Proxmox Plasmoid" \
      "Auto-rebuild failed. Check $LOG_FILE for details."
  fi
}

# Hash of all resolved libplasma + libQt6 paths — distro-agnostic via ldconfig.
get_fingerprint() {
  ldconfig -p 2>/dev/null \
    | grep -E 'libplasma|libQt6' \
    | awk '{print $NF}' \
    | sort \
    | xargs -r md5sum 2>/dev/null \
    | md5sum \
    | cut -d' ' -f1
}

if [ ! -d "$PLASMOID_DIR" ]; then
  log "ERROR: Plasmoid directory not found: $PLASMOID_DIR"
  notify_error
  exit 1
fi

if [ ! -f "$INSTALL_SCRIPT" ]; then
  log "ERROR: Install script not found: $INSTALL_SCRIPT"
  notify_error
  exit 1
fi

CURRENT_FINGERPRINT="$(get_fingerprint)"
STORED_FINGERPRINT=""
[ -f "$FINGERPRINT_FILE" ] && STORED_FINGERPRINT="$(cat "$FINGERPRINT_FILE")"

if [ "$CURRENT_FINGERPRINT" = "$STORED_FINGERPRINT" ]; then
  log "INFO: Fingerprint unchanged — no rebuild needed."
  exit 0
fi

log "INFO: Library change detected."
log "INFO:   stored:  ${STORED_FINGERPRINT:-<none>}"
log "INFO:   current: $CURRENT_FINGERPRINT"
log "INFO: Starting rebuild..."

if (cd "$SCRIPT_DIR" && bash "$INSTALL_SCRIPT" --no-deps >> "$LOG_FILE" 2>&1); then
  printf '%s' "$CURRENT_FINGERPRINT" > "$FINGERPRINT_FILE"
  log "INFO: Rebuild and reinstall succeeded."
else
  log "ERROR: Rebuild failed. Plasmoid may be broken until next successful rebuild."
  notify_error
  exit 1
fi
