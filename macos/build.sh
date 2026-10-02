#!/usr/bin/env bash
#
# $APP_NAME for macOS — build menu (same style as android/build.sh). Run it on a Mac (the .dmg can only be made there).
#   Desktop app = the shared window UI (../ui) driving tailscaled in the shared Electron shell (../electron), packaged as .dmg + .zip (Apple Silicon and Intel).
#   Non-interactive: macos/build.sh 1 3
#
set -uo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=../scripts/common.sh
ELECTRON_OS=mac      # target of the helper hooks in scripts/app-hooks.sh (linux | windows | mac)
TOOLS_PLATFORM=macos     # downloaded tools go to $TOOLS_ROOT/macos (Mac: /Users/dellsir/Documents/31_macos/bin/macos)
source "$ROOT_DIR/../scripts/common.sh"
: "${MACOS_EXPORT_DIR:=$SYNC_ROOT/macos/$EXPORT_SUB}"
: "${MACOS_TARGETS:=dmg zip}"
# One CPU by default (this Mac's own): a universal app carries two copies of Electron (~2x the size). MACOS_ARCH=--universal for one app that runs on both.
: "${MACOS_ARCH:=$([[ "$(uname -m)" == arm64 ]] && echo --arm64 || echo --x64)}"

need_mac() { [[ "$(uname -s)" == "Darwin" ]] || { err "The macOS app can only be built on a Mac. Option 2 (icons) works anywhere with ImageMagick."; return 1; }; }

action_install() {
  header "1) Install tools"
  need_mac || return
  ensure_node || return
    [[ -n "$(convert_bin)" ]] || warn "ImageMagick missing (only needed for option 2): brew install imagemagick"
  ok "Node.js $(node -v)"
}

action_icons() {
  header "2) Make icons from PNG (macOS)"
  need_icon_tools && find_icon_src || return 1
  local src="$ICON_FOUND" set="$REPO_DIR/tmp/AppIcon.iconset" spec name size
  mkdir -p "$set" "$ELECTRON_DIR/build"
  # Names follow Apple's iconutil convention exactly.
  for spec in icon_16x16:16 icon_16x16@2x:32 icon_32x32:32 icon_32x32@2x:64 icon_128x128:128 icon_128x128@2x:256 \
              icon_256x256:256 icon_256x256@2x:512 icon_512x512:512 icon_512x512@2x:1024; do
    IFS=':' read -r name size <<< "$spec"
    resize_icon "$src" "$size" "$set/$name.png"
  done
  resize_icon "$src" 512 "$ELECTRON_DIR/build/icon.png"
  make_web_icon "$src"
  if have iconutil; then
    iconutil -c icns -o "$ELECTRON_DIR/build/icon.icns" "$set" && ok "icon.icns -> electron/build/icon.icns"
  elif have png2icns; then
    png2icns "$ELECTRON_DIR/build/icon.icns" "$set"/icon_16x16.png "$set"/icon_32x32.png "$set"/icon_128x128.png "$set"/icon_256x256.png "$set"/icon_512x512.png \
      && ok "icon.icns (png2icns) -> electron/build/icon.icns"
  else
    warn "No iconutil (macOS) or png2icns: electron-builder will convert build/icon.png itself on a Mac."
  fi
}

action_build() {
  header "3) Make the macOS app -> $MACOS_EXPORT_DIR"
  ask_default MACOS_EXPORT_DIR "Save the result (dmg, zip) to"
  need_mac || return
  electron_prepare || return
  [[ -f "$ELECTRON_DIR/build/icon.png" ]] || { need_icon_tools && action_icons; }
  # shellcheck disable=SC2086
  rm -rf "$ELECTRON_DIR/dist"     # so only this build's files are exported
  (cd "$ELECTRON_DIR" && CSC_IDENTITY_AUTO_DISCOVERY="${CSC_IDENTITY_AUTO_DISCOVERY:-false}" npx electron-builder --mac $MACOS_TARGETS $MACOS_ARCH --publish never) \
    || { err "electron-builder failed."; return 1; }
  electron_tidy_dist
  export_to "$MACOS_EXPORT_DIR" "$ELECTRON_DIR"/dist/*.dmg "$ELECTRON_DIR"/dist/*.zip
  info "Not signed/notarized by default: first launch via right-click -> Open. To sign, set CSC_NAME / APPLE_ID env vars for electron-builder and CSC_IDENTITY_AUTO_DISCOVERY=true."
}

action_dev() { header "4) Run in a window (no packaging)"; need_mac || return; electron_run_dev; }
action_env() {
  header "Build environment"
  printf 'ui:       %s\nshell:    %s\nexport:   %s\ntargets:  %s %s\nicon src: %s\n' "$WEB_DIR" "$ELECTRON_DIR" "$MACOS_EXPORT_DIR" "$MACOS_TARGETS" "$MACOS_ARCH" "$ICON_SRC"
  use_private_node; have node && printf 'node:     %s\n' "$(node -v)" || echo "node:     not installed (option 1)"
  [[ -d "$ELECTRON_DIR/node_modules/electron" ]] && echo "electron: installed" || echo "electron: not installed yet"
}

print_menu() {
  cat <<MENU

${BOLD}$APP_NAME macOS app ($(date +%Y-%m-%d))${RESET}   (run on a Mac)
  1) Install tools (Node.js) -> $TOOLS_DIR
  2) Make icons from PNG (default $ICON_SRC; you can type another)
  3) Make the app ($MACOS_TARGETS) -> $MACOS_EXPORT_DIR
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
