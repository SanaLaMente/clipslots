#!/bin/bash
# ClipSlots — desinstalador.
#
#   curl -fsSL https://raw.githubusercontent.com/SanaLaMente/clipslots/main/uninstall.sh | bash
#
# Saca la app, el inicio automático y el permiso de Accesibilidad. Tus slots
# quedan guardados salvo que pases --purge:
#
#   curl -fsSL https://raw.githubusercontent.com/SanaLaMente/clipslots/main/uninstall.sh | bash -s -- --purge

main() {
  set -euo pipefail

  local ID="com.clipslots.app"
  local NAME="ClipSlots"
  local DATA="$HOME/Library/Application Support/$NAME"

  launchctl bootout "gui/$(id -u)/$ID" >/dev/null 2>&1 || true
  pkill -x "$NAME" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/LaunchAgents/$ID.plist"
  rm -rf "/Applications/$NAME.app" "$HOME/Applications/$NAME.app"
  tccutil reset Accessibility "$ID" >/dev/null 2>&1 || true

  if [ "${1:-}" = "--purge" ]; then
    rm -rf "$DATA"
    printf '\n  ClipSlots y tus slots fueron eliminados.\n\n'
  else
    printf '\n  ClipSlots fue desinstalado. Tus slots siguen en:\n    %s\n\n' "$DATA"
  fi
}

main "$@"
