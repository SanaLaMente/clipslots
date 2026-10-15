#!/bin/bash
# ClipSlots — instalador de un comando.
#
#   curl -fsSL https://raw.githubusercontent.com/SanaLaMente/clipslots/main/install.sh | bash
#
# Qué hace, en orden:
#   1. chequea que sea una Mac con macOS 11+ y que no corra con sudo;
#   2. consigue el código fuente (el clon local, o GitHub por HTTPS);
#   3. lo compila con swiftc en tu Mac y lo firma ad-hoc;
#   4. lo instala en Applications y lo deja arrancando al iniciar sesión.
#
# No pide contraseña ni manda nada a ningún servidor. Para desinstalar:
#
#   curl -fsSL https://raw.githubusercontent.com/SanaLaMente/clipslots/main/uninstall.sh | bash
#
# Todo vive dentro de main(), llamado en la última línea, para que una
# descarga cortada a la mitad nunca ejecute medio script.

main() {
  set -euo pipefail
  umask 022

  local REPO="${CLIPSLOTS_REPO:-SanaLaMente/clipslots}"
  local REF="${CLIPSLOTS_REF:-main}"
  local RAW="https://raw.githubusercontent.com/$REPO/$REF"
  local ID="com.clipslots.app"
  local NAME="ClipSlots"
  local AGENT="$HOME/Library/LaunchAgents/$ID.plist"

  fail() { printf '\n  ✗ %s\n\n' "$*" >&2; exit 1; }
  step() { printf '  · %s\n' "$*"; }

  printf '\n  ClipSlots para Mac\n\n'

  # ------------------------------------------------------------ esta Mac
  [ "$(uname -s)" = "Darwin" ] || fail "ClipSlots es solo para macOS."
  [ "$(id -u)" != "0" ] || fail "Corrélo sin sudo: se instala para tu usuario."
  local OS; OS="$(sw_vers -productVersion)"
  [ "${OS%%.*}" -ge 11 ] || fail "Necesita macOS 11 o superior (tenés $OS)."
  xcrun --sdk macosx --find swiftc >/dev/null 2>&1 \
    || fail "Falta el compilador de Swift. Instalá las Command Line Tools con: xcode-select --install"

  local TMP; TMP="$(mktemp -d)"
  # Se expande ahora, no cuando dispara el trap: para entonces main() terminó.
  trap "rm -rf '$TMP'" EXIT

  # ------------------------------------------------------------ código
  # Corrido desde un clon usa ese código; con curl | bash lo baja de GitHub.
  local SRC=""
  local here="${BASH_SOURCE[0]:-}"
  if [ -n "$here" ] && [ -f "$(dirname "$here")/Sources/main.swift" ]; then
    SRC="$(cd "$(dirname "$here")" && pwd)"
    step "Código local: $SRC"
  else
    step "Descargando el código de $REPO@$REF"
    SRC="$TMP/src"
    mkdir -p "$SRC/Sources"
    local file
    for file in Sources/main.swift Info.plist; do
      curl -fsSL --proto '=https' --tlsv1.2 --retry 2 "$RAW/$file" -o "$SRC/$file" \
        || fail "No pude descargar $file de $RAW."
    done
  fi

  # ------------------------------------------------------------ compilar
  step "Compilando para $(uname -m)"
  local APP="$TMP/$NAME.app"
  mkdir -p "$APP/Contents/MacOS"
  cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
  # Por xcrun, no por la ruta del toolchain: xcrun le pasa el SDK de macOS,
  # y sin SDK swiftc no encuentra la standard library.
  xcrun --sdk macosx swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos11.0" \
    "$SRC/Sources/main.swift" -o "$APP/Contents/MacOS/$NAME" 2> "$TMP/build.log" \
    || { cat "$TMP/build.log" >&2; fail "La compilación falló."; }
  # Firma ad-hoc: sin ella macOS no ejecuta binarios arm64 ni recuerda el permiso.
  codesign --force --sign - --identifier "$ID" "$APP" >/dev/null 2>&1 \
    || fail "No pude firmar la app."

  # ------------------------------------------------------------ instalar
  local DEST="/Applications/$NAME.app"
  if [ ! -w /Applications ]; then
    mkdir -p "$HOME/Applications"
    DEST="$HOME/Applications/$NAME.app"
  fi
  local UPDATING=""
  if [ -d "/Applications/$NAME.app" ] || [ -d "$HOME/Applications/$NAME.app" ]; then UPDATING=1; fi

  step "Instalando en $DEST"
  launchctl bootout "gui/$(id -u)/$ID" >/dev/null 2>&1 || true
  pkill -x "$NAME" >/dev/null 2>&1 || true
  rm -rf "/Applications/$NAME.app" "$HOME/Applications/$NAME.app" 2>/dev/null || true
  ditto "$APP" "$DEST"

  # Cada compilación ad-hoc tiene otra firma, y macOS ata el permiso de
  # Accesibilidad a la firma: el viejo queda "activado" pero ya no sirve.
  # Lo borramos para que macOS vuelva a preguntar limpio.
  if [ -n "$UPDATING" ]; then
    tccutil reset Accessibility "$ID" >/dev/null 2>&1 || true
  fi

  # ------------------------------------------------------------ arranque
  step "Configurando el inicio automático"
  mkdir -p "$(dirname "$AGENT")"
  cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$ID</string>
  <key>ProgramArguments</key>
  <array>
    <string>$DEST/Contents/MacOS/$NAME</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>ProcessType</key>
  <string>Interactive</string>
</dict>
</plist>
EOF
  launchctl bootstrap "gui/$(id -u)" "$AGENT" >/dev/null 2>&1 || open "$DEST"

  printf '\n  ClipSlots está instalado. Te queda un paso:\n\n'
  printf '    1  Activá ClipSlots en Ajustes del Sistema → Privacidad y seguridad → Accesibilidad.\n'
  printf '       (macOS te lo va a pedir solo; el ícono aparece arriba a la derecha.)\n\n'
  printf '    ⌘C + 1  guarda lo copiado en el slot 1      ⌘V + 1  pega el slot 1\n'
  printf '    (con ⌘ y la C o la V apretadas, tocás el número)\n\n'
  printf '  Para actualizar, corré el mismo comando otra vez.\n\n'
}

main "$@"
