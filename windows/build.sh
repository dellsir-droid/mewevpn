#!/usr/bin/env bash
#
# $APP_NAME for Windows — build menu (same style as android/build.sh).
#   Desktop app = the shared window UI (../ui) driving tailscaled in the shared Electron shell (../electron), packaged as a portable .zip and,
#   where it can be made (on Windows in Git Bash, or Linux/macOS with wine), a normal Setup .exe.
#   Run it in Git Bash / WSL on Windows, or on Linux/macOS (the .zip cross-builds without wine).
#   Non-interactive: windows/build.sh 1 3
#
set -uo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=../scripts/common.sh
ELECTRON_OS=windows      # target of the helper hooks in scripts/app-hooks.sh (linux | windows | mac)
TOOLS_PLATFORM=windows     # downloaded tools go to $TOOLS_ROOT/windows (Mac: /Users/dellsir/Documents/31_macos/bin/windows)
source "$ROOT_DIR/../scripts/common.sh"
: "${WINDOWS_EXPORT_DIR:=$SYNC_ROOT/windows/$EXPORT_SUB}"
if [[ -z "${WINDOWS_TARGETS:-}" ]]; then
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WINDOWS_TARGETS="zip nsis" ;; *) have wine && WINDOWS_TARGETS="zip nsis" || WINDOWS_TARGETS="zip" ;; esac
fi

action_install() {
  header "1) Install tools"
  ensure_node || return
  [[ -n "$(convert_bin)" ]] || warn "ImageMagick not found (only needed for option 2): apt install imagemagick / brew install imagemagick / winget install ImageMagick.ImageMagick"
  [[ "$WINDOWS_TARGETS" == *nsis* ]] || warn "No wine on this machine, so only the .zip is built. For Setup.exe run this on Windows, or install wine."
  ok "Node.js $(node -v)"
}

action_icons() {
  header "2) Make icons from PNG (Windows)"
  need_icon_tools && find_icon_src || return 1
  local src="$ICON_FOUND" c; c="$(convert_bin)"
  mkdir -p "$ELECTRON_DIR/build"
  if [[ -n "$c" ]]; then
  "$c" -background none "$src" \( -clone 0 -resize 16x16 \) \( -clone 0 -resize 32x32 \) \( -clone 0 -resize 48x48 \) \
    \( -clone 0 -resize 64x64 \) \( -clone 0 -resize 128x128 \) \( -clone 0 -resize 256x256 \) -delete 0 "$ELECTRON_DIR/build/icon.ico"
  else node "$REPO_DIR/scripts/gen-icons.js" ico "$ELECTRON_DIR/build/icon.ico"; fi
  resize_icon "$src" 512 "$ELECTRON_DIR/build/icon.png"
  make_web_icon "$src"
  ok "icon.ico (16-256 px) -> electron/build/icon.ico"
}

action_build() {
  header "3) Make the Windows app -> $WINDOWS_EXPORT_DIR"
  ask_default WINDOWS_EXPORT_DIR "Save the result (zip, exe) to"
  electron_prepare || return
  [[ -f "$ELECTRON_DIR/build/icon.ico" ]] || { need_icon_tools && action_icons; }
  info "Targets: $WINDOWS_TARGETS"
  # shellcheck disable=SC2086
  rm -rf "$ELECTRON_DIR/dist"     # so only this build's files are exported
  (cd "$ELECTRON_DIR" && npx electron-builder --win $WINDOWS_TARGETS --x64 --publish never) || { err "electron-builder failed."; return 1; }
  electron_tidy_dist
  export_to "$WINDOWS_EXPORT_DIR" "$ELECTRON_DIR"/dist/*.zip "$ELECTRON_DIR"/dist/*.exe
  info "Unzip and run $APP_NAME.exe (not code-signed, so SmartScreen asks once: More info -> Run anyway)."
}

action_dev() { header "4) Run in a window (no packaging)"; electron_run_dev; }
action_env() {
  header "Build environment"
  printf 'ui:       %s\nshell:    %s\nexport:   %s\ntargets:  %s\nicon src: %s\n' "$WEB_DIR" "$ELECTRON_DIR" "$WINDOWS_EXPORT_DIR" "$WINDOWS_TARGETS" "$ICON_SRC"
  use_private_node; have node && printf 'node:     %s\n' "$(node -v)" || echo "node:     not installed (option 1)"
  [[ -d "$ELECTRON_DIR/node_modules/electron" ]] && echo "electron: installed" || echo "electron: not installed yet"
}

print_menu() {
  cat <<MENU

${BOLD}$APP_NAME Windows app ($(date +%Y-%m-%d))${RESET}
  1) Install tools (Node.js)
  2) Make icons from PNG (default $ICON_SRC; you can type another)
  3) Make the app ($WINDOWS_TARGETS) -> $WINDOWS_EXPORT_DIR
  4) Run in a window (no packaging)
  5) Show build environment
  6) Clean build artifacts
  7) Delete downloaded packages (node_modules, private Node.js)
  q) Quit
MENU
}
run_choice() {
  case "$1" in
    1) action_install ;; 2) action_icons ;; 3) action_build ;; 4) action_dev ;; 5) action_env ;;
    6) electron_clean ;; 7) electron_remove_modules ;;
    q|Q) return 1 ;; *) warn "Unknown option: $1" ;;
  esac
  return 0
}
run_menu print_menu run_choice "$@"
