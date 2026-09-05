#!/usr/bin/env bash
# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly DEFAULT_LOGO="${SCRIPT_DIR}/tmp/mewevpn.png"
selected_logo="${DEFAULT_LOGO}"

usage() {
  cat <<'USAGE'
Change the MeWeVPN Android launcher and in-app logo.

Usage:
  ./change-logo.sh                    Open the interactive menu
  ./change-logo.sh install            Install ImageMagick
  ./change-logo.sh replace [PNG]      Replace logos (default: tmp/mewevpn.png)
  ./change-logo.sh status [PNG]       Validate and show the selected PNG
USAGE
}

run_as_root() {
  if (( EUID == 0 )); then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Root access is required to install ImageMagick, but sudo is unavailable." >&2
    return 1
  fi
}

install_packages() {
  if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
    echo "ImageMagick is already installed."
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    run_as_root apt-get update
    run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y imagemagick
  elif command -v dnf >/dev/null 2>&1; then
    run_as_root dnf install -y ImageMagick
  elif command -v pacman >/dev/null 2>&1; then
    run_as_root pacman -Sy --needed --noconfirm imagemagick
  elif command -v brew >/dev/null 2>&1; then
    brew install imagemagick
  else
    echo "Unsupported package manager. Install ImageMagick manually." >&2
    return 1
  fi
}

image_command() {
  if command -v magick >/dev/null 2>&1; then
    printf '%s\n' magick
  elif command -v convert >/dev/null 2>&1; then
    printf '%s\n' convert
  else
    echo "ImageMagick is missing. Choose menu option 1 first." >&2
    return 1
  fi
}

validate_logo() {
  local logo="$1" tool format width height
  [[ -f "${logo}" ]] || { echo "PNG not found: ${logo}" >&2; return 1; }
  tool="$(image_command)"
  read -r format width height < <("${tool}" "${logo}" -format '%m %w %h\n' info:)
  [[ "${format}" == PNG ]] || { echo "Logo must be a PNG (found ${format})." >&2; return 1; }
  (( width > 0 && height > 0 )) || { echo "PNG dimensions are invalid." >&2; return 1; }
  printf 'Selected PNG: %s (%sx%s)\n' "${logo}" "${width}" "${height}"
}

render_logo() {
  local source="$1" output="$2" width="$3" height="$4" background="${5:-none}"
  local tool tmp
  tool="$(image_command)"
  tmp="${output}.tmp.${output##*.}"
  mkdir -p -- "$(dirname -- "${output}")"
  "${tool}" "${source}" -auto-orient -resize "${width}x${height}" \
    -background "${background}" -gravity center -extent "${width}x${height}" "${tmp}"
  mv -f -- "${tmp}" "${output}"
}

replace_logos() {
  local logo="$1" density size
  validate_logo "${logo}"

  for density_size in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
    density="${density_size%%:*}"
    size="${density_size##*:}"
    render_logo "${logo}" \
      "${SCRIPT_DIR}/android/src/main/res/drawable-${density}/mwe_launcher_foreground.png" \
      "${size}" "${size}"
  done

  for density_size in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    density="${density_size%%:*}"
    size="${density_size##*:}"
    render_logo "${logo}" "${SCRIPT_DIR}/android/src/main/res/mipmap-${density}/ic_launcher.webp" \
      "${size}" "${size}" '#1F1E1E'
    cp -f -- "${SCRIPT_DIR}/android/src/main/res/mipmap-${density}/ic_launcher.webp" \
      "${SCRIPT_DIR}/android/src/main/res/mipmap-${density}/ic_launcher_round.webp"
  done

  render_logo "${logo}" "${SCRIPT_DIR}/android/src/main/ic_launcher-playstore.png" 512 512 '#1F1E1E'
  render_logo "${logo}" "${SCRIPT_DIR}/android/src/main/res/drawable-xhdpi/tv_banner.png" 320 180 '#1F1E1E'
  echo "Replaced MeWeVPN launcher, Play Store, TV, and in-app logo assets."
}

menu() {
  while true; do
    cat <<MENU

MeWeVPN Logo Builder
  Current PNG: ${selected_logo}
  1) Install required package (ImageMagick)
  2) Select PNG
  3) Replace MeWeVPN logos
  4) Validate/show selected PNG
  5) Exit
MENU
    read -r -p 'Select an option [1-5]: ' choice
    case "${choice}" in
      1) install_packages ;;
      2)
        read -r -p "PNG path [${DEFAULT_LOGO}]: " input
        input="${input:-${DEFAULT_LOGO}}"
        [[ "${input}" == /* ]] || input="${PWD}/${input}"
        validate_logo "${input}" && selected_logo="${input}"
        ;;
      3) replace_logos "${selected_logo}" ;;
      4) validate_logo "${selected_logo}" ;;
      5) return ;;
      *) echo "Invalid selection: ${choice}" >&2 ;;
    esac
  done
}

case "${1:-}" in
  -h|--help) usage ;;
  install) (( $# == 1 )) || { usage >&2; exit 2; }; install_packages ;;
  replace) (( $# <= 2 )) || { usage >&2; exit 2; }; replace_logos "${2:-${DEFAULT_LOGO}}" ;;
  status) (( $# <= 2 )) || { usage >&2; exit 2; }; validate_logo "${2:-${DEFAULT_LOGO}}" ;;
  '') menu ;;
  *) usage >&2; exit 2 ;;
esac
