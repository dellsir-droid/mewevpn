#!/usr/bin/env bash
#
# $APP_NAME for iOS — build menu (same style as android/build.sh). Must run on a Mac with Xcode.
#   App = native SwiftUI app (Sources/): default server https://hs.m-we.org, sign-in through oidc.m-we.org (Headscale OIDC) in the system browser sheet.
#   The Xcode project is generated from project.yml with XcodeGen, so the repo holds no .xcodeproj.
#   Non-interactive: ios/build.sh 1 2 3
#
set -uo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=../scripts/common.sh
TOOLS_PLATFORM=ios     # downloaded tools go to $TOOLS_ROOT/ios (Mac: /Users/dellsir/Documents/31_macos/bin/ios)
source "$ROOT_DIR/../scripts/common.sh"
: "${IOS_EXPORT_DIR:=$SYNC_ROOT/ios/$EXPORT_SUB}"   # on a Mac: /Users/dellsir/SMB/k8snas001_sharedfolders/sync_p/software/ios/mewe
: "${IOS_SIMULATOR:=iPhone 15}"

need_mac() { [[ "$(uname -s)" == "Darwin" ]] || { err "iOS apps can only be built on a Mac with Xcode. Option 2 (icons) works anywhere with ImageMagick."; return 1; }; }

action_install() {
  header "1) Check / install tools"
  need_mac || return
  have xcodebuild || { err "Xcode is not installed (App Store), or run: sudo xcode-select -s /Applications/Xcode.app"; return 1; }
  ok "$(xcodebuild -version | head -1)"
  ensure_xcodegen || return 1
  [[ -n "$(convert_bin)" ]] || warn "ImageMagick (only for the icons option) has no standalone download: brew install imagemagick"
  ok "XcodeGen $(xcodegen --version 2>/dev/null)"
}

action_icons() {
  header "2) Make icons from PNG (iOS)"
  need_icon_tools && find_icon_src || return 1
  local src="$ICON_FOUND" dir="$ROOT_DIR/Assets.xcassets/AppIcon.appiconset" spec name px scale pt idiom json="" first=1
  mkdir -p "$dir"
  # name:pixels:scale:points:idiom (points explicit so iPad Pro's 83.5 is not truncated)
  for spec in "Icon-20@2x:40:2x:20:iphone" "Icon-20@3x:60:3x:20:iphone" "Icon-29@2x:58:2x:29:iphone" "Icon-29@3x:87:3x:29:iphone" \
    "Icon-40@2x:80:2x:40:iphone" "Icon-40@3x:120:3x:40:iphone" "Icon-60@2x:120:2x:60:iphone" "Icon-60@3x:180:3x:60:iphone" \
    "Icon-20-ipad:20:1x:20:ipad" "Icon-20-ipad@2x:40:2x:20:ipad" "Icon-29-ipad:29:1x:29:ipad" "Icon-29-ipad@2x:58:2x:29:ipad" \
    "Icon-40-ipad:40:1x:40:ipad" "Icon-40-ipad@2x:80:2x:40:ipad" "Icon-76-ipad:76:1x:76:ipad" "Icon-76-ipad@2x:152:2x:76:ipad" \
    "Icon-83.5-ipad@2x:167:2x:83.5:ipad" "Icon-1024:1024:1x:1024:ios-marketing"; do
    IFS=':' read -r name px scale pt idiom <<< "$spec"
    # iOS rejects transparent app icons, so flatten onto white (ICON_BG_COLOR) here only.
    "$(convert_bin)" -background "${ICON_BG_COLOR:-#FFFFFF}" "$src" -resize "${px}x${px}^" -gravity center -extent "${px}x${px}" -alpha remove -alpha off "$dir/$name.png"
    [[ $first -eq 0 ]] && json+=","; first=0
    json+="{\"filename\":\"$name.png\",\"idiom\":\"$idiom\",\"scale\":\"$scale\",\"size\":\"${pt}x${pt}\"}"
  done
  printf '{ "images": [ %s ], "info": { "author": "xcode", "version": 1 } }\n' "$json" > "$dir/Contents.json"
  printf '{ "info": { "author": "xcode", "version": 1 } }\n' > "$ROOT_DIR/Assets.xcassets/Contents.json"
  make_web_icon "$src"
  ok "AppIcon.appiconset -> ios/Assets.xcassets"
}

prepare() {
  ensure_xcodegen || return 1
  (cd "$ROOT_DIR" && xcodegen generate --quiet) || return 1
}

action_build() {
  header "3) Build the app (simulator)"
  ask_default IOS_EXPORT_DIR "Save the result (.zip with the .app) to"
  need_mac || return; prepare || return
  [[ -d "$ROOT_DIR/Assets.xcassets" ]] || { need_icon_tools && action_icons && prepare; }
  (cd "$ROOT_DIR" && xcodebuild -project $APP_PROJECT.xcodeproj -scheme $APP_PROJECT -configuration Debug \
     -destination "generic/platform=iOS Simulator" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build) || { err "xcodebuild failed."; return 1; }
  local out="$ROOT_DIR/build/result"; rm -rf "$out"; mkdir -p "$out"
  # An .app is a folder, not a file you can send or install: ship it as ONE zip (ditto keeps the bundle intact).
  cp -R "$ROOT_DIR/build/Build/Products/Debug-iphonesimulator/$APP_PROJECT.app" "$out/$APP_PROJECT.app"
  ditto -c -k --sequesterRsrc --keepParent "$out/$APP_PROJECT.app" "$out/$(result_name zip)" || { err "Could not zip the app."; return 1; }
  export_to "$IOS_EXPORT_DIR" "$out/$(result_name zip)"
  info "Simulator: unzip, then drag $APP_PROJECT.app onto the Simulator (or: xcrun simctl install booted $APP_PROJECT.app). An iPhone needs option 4 (signed .ipa)."
}

action_archive() {
  header "4) Archive for a device / TestFlight (.ipa)"
  need_mac || return
  [[ -n "${DEVELOPMENT_TEAM:-}" ]] || { err "Set your Apple team first:  DEVELOPMENT_TEAM=ABCDE12345 ./build.sh 4   (needs an Apple Developer account and signing set up in Xcode)"; return 1; }
  prepare || return
  (cd "$ROOT_DIR" && xcodebuild -project $APP_PROJECT.xcodeproj -scheme $APP_PROJECT -configuration Release -destination "generic/platform=iOS" \
     -archivePath build/$APP_PROJECT.xcarchive DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" -allowProvisioningUpdates archive) || { err "Archive failed."; return 1; }
  cat > "$ROOT_DIR/build/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>method</key><string>${IOS_EXPORT_METHOD:-development}</string><key>teamID</key><string>$DEVELOPMENT_TEAM</string></dict></plist>
PLIST
  (cd "$ROOT_DIR" && xcodebuild -exportArchive -archivePath build/$APP_PROJECT.xcarchive -exportOptionsPlist build/export.plist -exportPath build/ipa -allowProvisioningUpdates) || { err "Export failed."; return 1; }
  local ipa; ipa="$(ls "$ROOT_DIR"/build/ipa/*.ipa 2>/dev/null | head -1)"
  [[ -n "$ipa" ]] || { err "No .ipa was produced."; return 1; }
  mkdir -p "$ROOT_DIR/build/result" && cp -f "$ipa" "$ROOT_DIR/build/result/$(result_name ipa)"
  export_to "$IOS_EXPORT_DIR" "$ROOT_DIR/build/result/$(result_name ipa)"
}

action_run() {
  header "5) Run in the iOS Simulator"
  need_mac || return
  local app="$ROOT_DIR/build/Build/Products/Debug-iphonesimulator/$APP_PROJECT.app"
  [[ -d "$app" ]] || { err "Build first (option 3)."; return 1; }
  xcrun simctl boot "$IOS_SIMULATOR" 2>/dev/null; open -a Simulator
  xcrun simctl install booted "$app" && xcrun simctl launch booted $APP_IOS_ID
}

action_env() {
  header "Build environment"
  printf 'web:     %s\nexport:  %s\nicon src: %s\nsimulator: %s\n' "$WEB_DIR" "$IOS_EXPORT_DIR" "$ICON_SRC" "$IOS_SIMULATOR"
  have xcodebuild && xcodebuild -version | head -2 || echo "xcode:   not available (Mac only)"
  have xcodegen && echo "xcodegen: $(xcodegen --version 2>/dev/null)" || echo "xcodegen: missing (option 1)"
}
action_clean() { rm -rf "$ROOT_DIR/build" "$ROOT_DIR/$APP_PROJECT.xcodeproj"; ok "Cleaned build and the generated project."; }

print_menu() {
  cat <<MENU

${BOLD}$APP_NAME iOS app ($(date +%Y-%m-%d))${RESET}   (Mac + Xcode)
  1) Install / check tools (Xcode, XcodeGen) -> $TOOLS_DIR
  2) Make icons from PNG (source: $ICON_SRC)
  3) Build the app for the Simulator -> $IOS_EXPORT_DIR
  4) Archive a signed .ipa (needs DEVELOPMENT_TEAM)
  5) Run in the iOS Simulator
  6) Show build environment
  7) Clean build artifacts
  q) Quit
MENU
}
run_choice() {
  case "$1" in
    1) action_install ;; 2) action_icons ;; 3) action_build ;; 4) action_archive ;; 5) action_run ;; 6) action_env ;; 7) action_clean ;;
    q|Q) return 1 ;; *) warn "Unknown option: $1" ;;
  esac
  return 0
}
run_menu print_menu run_choice "$@"
