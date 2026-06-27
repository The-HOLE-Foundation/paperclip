#!/usr/bin/env bash
# Install (or update) the paperclip systemd service from the in-repo unit file.
# Idempotent: safe to re-run after pulling new source.
#
# Usage:  sudo ./scripts/deploy/install-systemd.sh
set -euo pipefail

UNIT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paperclip.service"
UNIT_DST=/etc/systemd/system/paperclip.service

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

install -m 0644 "$UNIT_SRC" "$UNIT_DST"
systemctl daemon-reload
systemctl enable --now paperclip.service

echo
echo "Installed and started paperclip.service."
echo "  Status: systemctl status paperclip.service"
echo "  Logs:   journalctl -u paperclip -f"
