#!/usr/bin/env bash
# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly DEFAULT_OUTPUT="${SCRIPT_DIR}/MeWeVPN-debug.apk"
readonly LOCAL_ANDROID_SDK="${SCRIPT_DIR}/android-sdk"

usage() {
  cat <<'USAGE'
Build the MeWeVPN debug APK, including the Go networking library.

Usage:
  ./build-apk.sh                         Open the interactive build menu
  ./build-apk.sh menu                    Open the menu explicitly
  ./build-apk.sh build [OUTPUT_APK]      Build after packages have been installed
  ./build-apk.sh install-sdk             Install required Android build packages
  ./build-apk.sh clean                   Remove generated build artifacts
  ./build-apk.sh [OUTPUT_APK]            Build directly (backward compatible)

OUTPUT_APK defaults to ./MeWeVPN-debug.apk.
USAGE
}

configure_android_sdk() {
  local configured_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"

  # Keep a complete user-configured SDK. Distribution-provided SDK directories often contain only
  # platform tools and are not writable; use the ignored repo-local SDK when sdkmanager is absent.
  if [[ -n "${configured_sdk}" && -x "${configured_sdk}/cmdline-tools/latest/bin/sdkmanager" ]]; then
    export ANDROID_SDK_ROOT="${configured_sdk}"
  else
    export ANDROID_SDK_ROOT="${MWE_ANDROID_SDK_ROOT:-${LOCAL_ANDROID_SDK}}"
  fi
  export ANDROID_HOME="${ANDROID_SDK_ROOT}"
}

install_sdk() {
  configure_android_sdk
  echo "Installing Android SDK packages in ${ANDROID_SDK_ROOT}..."
  make -C "${SCRIPT_DIR}" androidsdk
}

sdk_is_ready() {
  make --silent -C "${SCRIPT_DIR}" checkandroidsdk >/dev/null 2>&1
}

require_sdk() {
  configure_android_sdk
  if ! sdk_is_ready; then
    cat >&2 <<'EOF'
The required Android SDK/NDK packages are not installed.
Run ./build-apk.sh and choose option 1, then choose option 2 to build the APK.
EOF
    return 1
  fi
}

build_apk() {
  local output="${1:-${DEFAULT_OUTPUT}}"
  if [[ "${output}" != /* ]]; then
    output="${PWD}/${output}"
  fi

  mkdir -p -- "$(dirname -- "${output}")"
  require_sdk

  echo "Building MeWeVPN APK..."
  make -C "${SCRIPT_DIR}" apk
  install -m 0644 "${SCRIPT_DIR}/tailscale-debug.apk" "${output}"
  echo "MeWeVPN APK written to ${output}"
}

show_environment() {
  configure_android_sdk
  printf 'Repository:       %s\n' "${SCRIPT_DIR}"
  printf 'Android SDK:      %s\n' "${ANDROID_SDK_ROOT}"
  printf 'Default APK:      %s\n' "${DEFAULT_OUTPUT}"
  if sdk_is_ready; then
    echo 'SDK/NDK status:   ready'
  else
    echo 'SDK/NDK status:   packages need to be installed'
  fi
}

menu() {
  while true; do
    cat <<'MENU'

MeWeVPN APK Builder
  1) Install required packages
  2) Make the APK
  3) Exit
MENU
    read -r -p 'Select an option [1-3]: ' choice
    case "${choice}" in
      1) install_sdk ;;
      2)
        read -r -p "Output APK [${DEFAULT_OUTPUT}]: " output
        build_apk "${output:-${DEFAULT_OUTPUT}}"
        ;;
      3) return ;;
      *) echo "Invalid selection: ${choice}" >&2 ;;
    esac
  done
}

case "${1:-}" in
  -h|--help) usage ;;
  menu) (( $# == 1 )) || { usage >&2; exit 2; }; menu ;;
  install-sdk) (( $# == 1 )) || { usage >&2; exit 2; }; install_sdk ;;
  build) (( $# <= 2 )) || { usage >&2; exit 2; }; build_apk "${2:-${DEFAULT_OUTPUT}}" ;;
  clean) (( $# == 1 )) || { usage >&2; exit 2; }; make -C "${SCRIPT_DIR}" clean ;;
  '')
    if [[ -t 0 ]]; then
      menu
    else
      build_apk "${DEFAULT_OUTPUT}"
    fi
    ;;
  -*) usage >&2; exit 2 ;;
  *) (( $# == 1 )) || { usage >&2; exit 2; }; build_apk "$1" ;;
esac
