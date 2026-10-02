#!/usr/bin/env bash
#
# $APP_NAME for Linux — build menu (same style as android/build.sh).
#   Desktop app = the shared window UI (../ui) driving tailscaled in the shared Electron shell (../electron), packaged as AppImage + .deb + .tar.gz.
#   Non-interactive: linux/build.sh 1 3
#
set -uo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=../scripts/common.sh
ELECTRON_OS=linux      # target of the helper hooks in scripts/app-hooks.sh (linux | windows | mac)
TOOLS_PLATFORM=linux     # downloaded tools go to $TOOLS_ROOT/linux (Mac: /Users/dellsir/Documents/31_macos/bin/linux)
source "$ROOT_DIR/../scripts/common.sh"
LINUX_EXPORT_DIR="${LINUX_EXPORT_DIR:-$SYNC_ROOT/linux/$EXPORT_SUB}"
: "${LINUX_TARGETS:=AppImage deb tar.gz}"

action_install() {
  header "1) Install tools"
  ensure_node || return
  if [[ -z "$(convert_bin)" ]]; then
    warn "ImageMagick not found (only needed for option 2). Install: sudo apt install imagemagick  (or your distro's package)"
  fi
  have dpkg-deb || have fakeroot || warn "The .deb target needs dpkg + fakeroot (sudo apt install dpkg fakeroot); AppImage and tar.gz work without."
  ok "Node.js $(node -v)"
}

action_icons() {
  header "2) Make icons from PNG (Linux)"
  need_icon_tools && find_icon_src || return 1
  local src="$ICON_FOUND" base="$REPO_DIR/tmp/linux-icons" size
  for size in 16 22 24 32 48 64 96 128 256 512; do
    mkdir -p "$base/hicolor/${size}x${size}/apps" "$ELECTRON_DIR/build/icons"
    resize_icon "$src" "$size" "$base/hicolor/${size}x${size}/apps/$APP_SLUG.png"
    resize_icon "$src" "$size" "$ELECTRON_DIR/build/icons/${size}x${size}.png"     # electron-builder's linux icon set
  done
  resize_icon "$src" 512 "$ELECTRON_DIR/build/icon.png"
  make_web_icon "$src"
  cat > "$base/$APP_SLUG.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=$APP_DESC
Icon=$APP_SLUG
Exec=$APP_SLUG %U
Categories=$LINUX_CATEGORY
${APP_SCHEME:+MimeType=x-scheme-handler/$APP_SCHEME;}
DESK
  ok "Icons + ${APP_SLUG}.desktop -> electron/build (local only; the shared folder only receives the finished packages)"
}

action_build() {
  header "3) Make the Linux app -> $LINUX_EXPORT_DIR"
  ask_default LINUX_EXPORT_DIR "Save the result (AppImage, deb, tar.gz) to"
  electron_prepare || return
  [[ -f "$ELECTRON_DIR/build/icons/512x512.png" ]] || { need_icon_tools && action_icons; }
  # shellcheck disable=SC2086
  rm -rf "$ELECTRON_DIR/dist"     # so only this build's files are exported
  (cd "$ELECTRON_DIR" && npx electron-builder --linux $LINUX_TARGETS --publish never) || { err "electron-builder failed."; return 1; }
  electron_tidy_dist
  export_to "$LINUX_EXPORT_DIR" "$ELECTRON_DIR"/dist/*.AppImage "$ELECTRON_DIR"/dist/*.deb "$ELECTRON_DIR"/dist/*.tar.gz
  info "Run: chmod +x $APP_NAME-*.AppImage && ./$APP_NAME-*.AppImage   (or sudo apt install ./${APP_SLUG}_*.deb)"
}

action_dev() { header "4) Run in a window (no packaging)"; electron_run_dev; }
action_env() {
  header "Build environment"
  printf 'web:        %s\nshell:      %s\nexport:     %s\ntargets:    %s\nicon src:   %s\n' "$WEB_DIR" "$ELECTRON_DIR" "$LINUX_EXPORT_DIR" "$LINUX_TARGETS" "$ICON_SRC"
  use_private_node; have node && printf 'node:       %s (%s)\n' "$(node -v)" "$(command -v node)" || echo "node:       not installed (option 1)"
  [[ -d "$ELECTRON_DIR/node_modules/electron" ]] && echo "electron:   installed" || echo "electron:   not installed yet"
}

print_menu() {
  cat <<MENU

${BOLD}$APP_NAME Linux app ($(date +%Y-%m-%d))${RESET}
  1) Install tools (Node.js, no sudo)
  2) Make icons from PNG (default $ICON_SRC; you can type another)
  3) Make the app (AppImage, deb, tar.gz) -> $LINUX_EXPORT_DIR
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
