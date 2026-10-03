#!/usr/bin/env bash
#
# MeWeTail for Android — build menu (same style as the other mewe* repos).
#   The app is the open-source Tailscale Android client (Kotlin + Go, in this folder), rebranded, default server https://hs.m-we.org
#   (Headscale + OIDC sign-in through oidc.m-we.org). Built the way upstream does it: inside Docker, so only Docker is needed.
#   Non-interactive: android/build.sh 1 3
#
set -uo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd -P)"      # this folder (the old repo root: Makefile, go.mod, android/ module)
TOOLS_PLATFORM=android
# shellcheck source=../scripts/common.sh
source "$ROOT_DIR/../scripts/common.sh"
: "${ANDROID_EXPORT_DIR:=$SYNC_ROOT/android/$EXPORT_SUB}"
: "${USE_DOCKER:=auto}"        # auto = Docker if installed, else this machine's JDK + Android SDK/NDK + Go; 1 = always Docker; 0 = never (make tailscale-debug)
# Docker is only upstream's way to get the exact SDK/NDK/Go toolchain without installing it. It is not required.
if [[ "$USE_DOCKER" == auto ]]; then if command -v docker >/dev/null 2>&1; then USE_DOCKER=1; else USE_DOCKER=0; fi; fi
: "${ICON_BG_COLOR:=#FFFFFF}"  # behind the adaptive-icon foreground
RES="$ROOT_DIR/android/src/main/res"

need_docker() { have docker || { err "Docker is required (https://docs.docker.com/engine/install/). Or set USE_DOCKER=0 to build with a local Android SDK/NDK + Go."; return 1; }; }

# tailscale.version: upstream makes it with git; the Docker build only sees this folder, so write it here (keys the Makefile and Gradle read).
write_version_file() {
  local core short hash
  core="$(grep -E '^\s*tailscale\.com\s' "$ROOT_DIR/go.mod" | head -1 | awk '{print $2}')"; short="${core#v}"; short="${short%%-*}"
  hash="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo mewetail)"
  cat > "$ROOT_DIR/tailscale.version" <<VER
VERSION_NAME=$APP_VERSION
VERSION_SHORT=$short
VERSION_LONG=$short-mewetail.$APP_VERSION
VERSION_GIT_HASH=$hash
VERSION_EXTRA_HASH=
VERSION_TRACK=unstable
VER
  touch "$ROOT_DIR/tailscale.version"        # newer than go.mod so make keeps it
}

action_install() {
  header "1) Install tools (Docker build image)"
  if [[ "$USE_DOCKER" == 1 ]]; then
    need_docker || return 1
    info "Building the Android build image (once; downloads the SDK/NDK, ~10 min)…"
    (cd "$ROOT_DIR" && make docker-build-image) || { err "Docker image build failed."; return 1; }
    ok "Docker build image ready."
  else
    (cd "$ROOT_DIR" && make androidsdk) || return 1
  fi
  [[ -n "$(convert_bin)" ]] || warn "ImageMagick not found (only for option 2 with your own PNG): the bundled icon works without it."
}

action_icons() {
  header "2) Make icons from PNG (Android)"
  need_icon_tools && find_icon_src || return 1
  local src="$ICON_FOUND" d size
  local bundled=0; [[ "$src" == "$REPO_DIR/design/"* ]] && bundled=1
  # The bundled icon is drawn with Node: fetch a private Node if there is none (no sudo). Never report [ok] when nothing was made.
  if [[ $bundled == 1 || -z "$(convert_bin)" ]] && ! have node; then ensure_node || { err "Node.js (or ImageMagick) is needed to make icons. The icons already in the repo are unchanged."; return 1; }; fi
  if [[ -z "$(convert_bin)" && $bundled == 0 ]]; then warn "ImageMagick is needed to use your own PNG ($src): using the bundled icon instead."; bundled=1; fi
  # legacy launcher icons (square + round)
  for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    size="${d#*:}"; d="${d%%:*}"
    mkdir -p "$RES/mipmap-$d"; rm -f "$RES/mipmap-$d"/ic_launcher*.webp
    resize_icon "$src" "$size" "$RES/mipmap-$d/ic_launcher.png"
    if [[ $bundled == 0 ]]; then
      "$(convert_bin)" "$RES/mipmap-$d/ic_launcher.png" \( -size "${size}x${size}" xc:none -fill white -draw "circle $((size/2)),$((size/2)) $((size/2)),0" \) -compose DstIn -composite "$RES/mipmap-$d/ic_launcher_round.png"
    else cp "$RES/mipmap-$d/ic_launcher.png" "$RES/mipmap-$d/ic_launcher_round.png"; fi
  done
  # adaptive icon: foreground art inside the safe zone on a solid background (replaces upstream's vector foreground)
  mkdir -p "$RES/drawable-nodpi"; rm -f "$RES/drawable/ic_launcher_foreground.xml"
  if [[ $bundled == 0 ]]; then
    "$(convert_bin)" -background none "$src" -resize 66% -gravity center -background none -extent 100%x100% -resize 432x432 "$RES/drawable-nodpi/ic_launcher_foreground.png" 2>/dev/null \
      || "$(convert_bin)" -background none "$src" -resize 285x285 -gravity center -extent 432x432 "$RES/drawable-nodpi/ic_launcher_foreground.png"
  else node "$REPO_DIR/scripts/gen-icons.js" png 432 "$RES/drawable-nodpi/ic_launcher_foreground.png" foreground; fi
  printf '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">%s</color>\n</resources>\n' "$ICON_BG_COLOR" > "$RES/values/ic_launcher_background.xml"
  for f in ic_launcher ic_launcher_round; do
    printf '<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/ic_launcher_background"/>\n    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n</adaptive-icon>\n' > "$RES/mipmap-anydpi-v26/$f.xml"
  done
  resize_icon "$src" 512 "$ROOT_DIR/android/src/main/ic_launcher-playstore.png"
  # Android TV banner (320x180)
  if [[ $bundled == 0 ]]; then
    "$(convert_bin)" -size 320x180 "xc:$ICON_BG_COLOR" \( "$src" -resize 140x140 \) -gravity center -composite "$RES/drawable-xhdpi/tv_banner.png"
  else node "$REPO_DIR/scripts/gen-icons.js" png 320 "$RES/drawable-xhdpi/tv_banner.png" banner; fi
  ok "Launcher icons, adaptive icon, Play Store icon and TV banner -> android/android/src/main"
}

# run_make TARGET : the upstream Makefile target, in Docker (default) or locally
run_make() {
  local target="$1"
  if [[ "$USE_DOCKER" == 1 ]]; then need_docker || return 1; (cd "$ROOT_DIR" && make "docker-$target"); else (cd "$ROOT_DIR" && make "$target"); fi
}

action_build() {
  header "3) Make the APK -> $ANDROID_EXPORT_DIR"
  ask_default ANDROID_EXPORT_DIR "Save the result (apk) to"
  write_version_file
  rm -f "$ROOT_DIR/tailscale-debug.apk"
  run_make tailscale-debug || { err "Build failed (see above)."; return 1; }
  [[ -f "$ROOT_DIR/tailscale-debug.apk" ]] || { err "tailscale-debug.apk was not produced."; return 1; }
  local out; out="$ROOT_DIR/tmp/$(result_name apk)"; mkdir -p "$ROOT_DIR/tmp"; cp "$ROOT_DIR/tailscale-debug.apk" "$out"
  export_to "$ANDROID_EXPORT_DIR" "$out"
  info "Signed with the (stable) debug key: fine for sideloading. For the Play Store use option 4."
}

action_release() {
  header "4) Make the signed release bundle (.aab)"
  [[ -n "${JKS_PATH:-}" && -n "${JKS_PASSWORD:-}" ]] || { err "Set JKS_PATH (keystore) and JKS_PASSWORD, with a key alias named 'tailscale' (see Makefile 'release')."; return 1; }
  ask_default ANDROID_EXPORT_DIR "Save the result (aab) to"
  write_version_file
  (cd "$ROOT_DIR" && if [[ "$USE_DOCKER" == 1 ]]; then make docker-run-build; else make release; fi) || { err "Release build failed."; return 1; }
  local out; out="$ROOT_DIR/tmp/$(result_name aab)"; mkdir -p "$ROOT_DIR/tmp"; cp "$ROOT_DIR/tailscale-release.aab" "$out" && export_to "$ANDROID_EXPORT_DIR" "$out"
}

action_env() {
  header "Build environment"
  printf 'project:  %s\nexport:   %s\nicon src: %s (bundled fallback: %s)\nversion:  %s\ndocker:   %s\nserver:   %s (default in the app, editable in its login screen)\n' \
    "$ROOT_DIR" "$ANDROID_EXPORT_DIR" "$ICON_SRC" "$REPO_DIR/design/$ICON_NAME" "$APP_VERSION" "$([[ "$USE_DOCKER" == 1 ]] && echo "yes (USE_DOCKER=0 for local tools)" || echo no)" "$CONTROL_URL"
  have docker && echo "docker:   $(docker --version)" || echo "docker:   not installed"
}
action_clean() { header "Clean"; rm -rf "$ROOT_DIR/android/build" "$ROOT_DIR/android/libs" "$ROOT_DIR/tailscale-debug.apk" "$ROOT_DIR/tailscale-release.aab" "$ROOT_DIR/tailscale.version" "$ROOT_DIR/tmp"; ok "Cleaned build outputs."; }
action_rmimage() { header "Remove the Docker build image"; need_docker || return 1; confirm "Remove the image (re-built by option 1)?" && (cd "$ROOT_DIR" && make docker-remove-build-image); }

print_menu() {
  cat <<MENU

${BOLD}$APP_NAME Android app ($(date +%Y-%m-%d))${RESET}   default server $CONTROL_URL
  1) Install tools ($([[ "$USE_DOCKER" == 1 ]] && echo "build the Docker image once" || echo "Android SDK/NDK on this machine; needs JDK 17+ and Go"))
  2) Make icons from PNG (default $ICON_SRC; you can type another)
  3) Make the app (APK) -> $ANDROID_EXPORT_DIR
  4) Make the signed release bundle (AAB, needs JKS_PATH + JKS_PASSWORD)
  5) Show build environment
  6) Clean build outputs
  7) Remove the Docker build image (Docker mode only)
  q) Quit
MENU
}
run_choice() {
  case "$1" in
    1) action_install ;; 2) action_icons ;; 3) action_build ;; 4) action_release ;; 5) action_env ;;
    6) action_clean ;; 7) action_rmimage ;;
    q|Q) return 1 ;; *) warn "Unknown option: $1" ;;
  esac
  return 0
}
run_menu print_menu run_choice "$@"
