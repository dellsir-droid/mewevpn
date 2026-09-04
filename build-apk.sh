#!/usr/bin/env bash
# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TMP_DIR="${SCRIPT_DIR}/tmp"
readonly PACKAGE_CACHE="${TMP_DIR}/package"
readonly DEFAULT_OUTPUT="${TMP_DIR}/MeWeVPN-debug.apk"
readonly LOCAL_ANDROID_SDK="${SCRIPT_DIR}/android-sdk"

usage() {
  cat <<'USAGE'
Build the MeWeVPN debug APK, including the Go networking library.

Usage:
  ./build-apk.sh                         Open the interactive build menu
  ./build-apk.sh menu                    Open the menu explicitly
  ./build-apk.sh build [OUTPUT_APK]      Build after packages have been installed
  ./build-apk.sh install                 Install host, Android SDK, and NDK packages
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

configure_build_cache() {
  export GRADLE_USER_HOME="${PACKAGE_CACHE}/gradle-home"
  export GOPATH="${PACKAGE_CACHE}/go"
  export GOMODCACHE="${GOPATH}/pkg/mod"
  export GOCACHE="${PACKAGE_CACHE}/go-build"
  export TAILSCALE_TOOLCHAIN_CACHE="${PACKAGE_CACHE}/tailscale-go"
  mkdir -p "${GRADLE_USER_HOME}" "${GOMODCACHE}" "${GOCACHE}"

  local gradle_bin
  gradle_bin="$(find "${PACKAGE_CACHE}" -maxdepth 3 -type f -path '*/bin/gradle' -print -quit 2>/dev/null || true)"
  if [[ -n "${gradle_bin}" ]]; then
    export GRADLE="${gradle_bin}"
  else
    unset GRADLE || true
  fi
}

configure_java() {
  local candidate major
  local -a candidates=()

  [[ -n "${JAVA_HOME:-}" ]] && candidates+=("${JAVA_HOME}")
  shopt -s nullglob
  candidates+=(
    /usr/lib/jvm/java-17-openjdk-*
    /usr/lib/jvm/temurin-17-*
    /usr/lib/jvm/java-21-openjdk-*
    "${HOME}"/.local/share/mise/installs/java/17*
    "${HOME}"/.local/share/mise/installs/java/21*
  )
  shopt -u nullglob

  for candidate in "${candidates[@]}"; do
    [[ -x "${candidate}/bin/java" ]] || continue
    major="$("${candidate}/bin/java" -version 2>&1 | awk -F '[".]' '/version/ {print $2; exit}')"
    if [[ "${major}" =~ ^[0-9]+$ ]] && (( major >= 17 && major <= 24 )); then
      export JAVA_HOME="${candidate}"
      export PATH="${JAVA_HOME}/bin:${PATH}"
      return 0
    fi
  done

  if command -v java >/dev/null 2>&1; then
    major="$(java -version 2>&1 | awk -F '[".]' '/version/ {print $2; exit}')"
    if [[ "${major}" =~ ^[0-9]+$ ]] && (( major >= 17 && major <= 24 )); then
      export JAVA_HOME="$(dirname -- "$(dirname -- "$(readlink -f -- "$(command -v java)")")")"
      return 0
    fi
  fi
  return 1
}

run_as_root() {
  if (( EUID == 0 )); then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Root access is required to install host packages, but sudo is unavailable." >&2
    return 1
  fi
}

install_host_packages() {
  if configure_java && command -v curl >/dev/null && command -v unzip >/dev/null &&
      command -v make >/dev/null && command -v git >/dev/null &&
      (command -v sha256sum >/dev/null || command -v shasum >/dev/null); then
    echo "Host build packages are already installed (JAVA_HOME=${JAVA_HOME})."
    return
  fi

  echo "Installing Java and host build packages..."
  if command -v apt-get >/dev/null 2>&1; then
    run_as_root apt-get update
    if ! run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        openjdk-17-jdk-headless ca-certificates curl git make perl unzip zip; then
      run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        openjdk-21-jdk-headless ca-certificates curl git make perl unzip zip
    fi
  elif command -v dnf >/dev/null 2>&1; then
    run_as_root dnf install -y java-17-openjdk-devel ca-certificates curl git make perl-Digest-SHA unzip zip
  elif command -v pacman >/dev/null 2>&1; then
    run_as_root pacman -Sy --needed --noconfirm jdk17-openjdk ca-certificates curl git make perl unzip zip
  elif command -v brew >/dev/null 2>&1; then
    brew install openjdk@17 curl git make perl unzip
  else
    echo "Unsupported package manager. Install JDK 17, curl, git, make, perl, unzip, and zip." >&2
    return 1
  fi

  configure_java || {
    echo "A compatible JDK (17 through 24) was not found after installation." >&2
    return 1
  }
  echo "Using JAVA_HOME=${JAVA_HOME}"
}

install_sdk() {
  configure_java || {
    echo "Java is missing. Run option 1 to install all required packages." >&2
    return 1
  }
  configure_android_sdk
  echo "Installing Android SDK packages in ${ANDROID_SDK_ROOT}..."
  make -C "${SCRIPT_DIR}" androidsdk
}

install_gradle() {
  local properties="${SCRIPT_DIR}/android/gradle/wrapper/gradle-wrapper.properties"
  local url checksum archive version_dir
  url="$(sed -n 's/^distributionUrl=//p' "${properties}" | sed 's/\\:/:/')"
  checksum="$(sed -n 's/^distributionSha256Sum=//p' "${properties}")"
  archive="${PACKAGE_CACHE}/${url##*/}"
  version_dir="${PACKAGE_CACHE}/${archive##*/}"
  version_dir="${version_dir%-bin.zip}"

  if [[ -x "${version_dir}/bin/gradle" ]]; then
    export GRADLE="${version_dir}/bin/gradle"
    echo "Using cached Gradle at ${GRADLE}."
    return
  fi

  mkdir -p "${PACKAGE_CACHE}"
  "${SCRIPT_DIR}/scripts/download-file.sh" "${url}" "${archive}"
  "${SCRIPT_DIR}/scripts/check-sha256.sh" "${checksum}" "${archive}"
  if [[ ! -x "${version_dir}/bin/gradle" ]]; then
    echo "Extracting ${archive##*/} in ${PACKAGE_CACHE}..."
    unzip -q -o "${archive}" -d "${PACKAGE_CACHE}"
  fi
  export GRADLE="${version_dir}/bin/gradle"
}

install_required_packages() {
  install_host_packages
  configure_build_cache
  install_gradle
  install_sdk
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

  configure_build_cache
  mkdir -p -- "$(dirname -- "${output}")"
  configure_java || {
    echo "Java is missing. Run ./build-apk.sh and choose option 1 first." >&2
    return 1
  }
  require_sdk
  if [[ -z "${GRADLE:-}" || ! -x "${GRADLE}" ]]; then
    echo "Gradle is not installed in ${PACKAGE_CACHE}. Run menu option 1 first." >&2
    return 1
  fi

  echo "Building MeWeVPN APK..."
  make -C "${SCRIPT_DIR}" apk
  install -m 0644 "${SCRIPT_DIR}/tailscale-debug.apk" "${output}"
  echo "MeWeVPN APK written to ${output}"
}

show_environment() {
  configure_build_cache
  configure_android_sdk
  printf 'Repository:       %s\n' "${SCRIPT_DIR}"
  printf 'Android SDK:      %s\n' "${ANDROID_SDK_ROOT}"
  printf 'Default APK:      %s\n' "${DEFAULT_OUTPUT}"
  printf 'Package cache:    %s\n' "${PACKAGE_CACHE}"
  printf 'Gradle:           %s\n' "${GRADLE:-not installed}"
  if configure_java; then
    printf 'Java home:        %s\n' "${JAVA_HOME}"
  else
    echo 'Java status:      JDK 17-24 needs to be installed'
  fi
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
  1) Install required packages (Java + Android SDK/NDK)
  2) Make the APK
  3) Show build environment
  4) Clean build artifacts (keep downloaded packages)
  5) Delete downloaded package cache
  6) Exit
MENU
    read -r -p 'Select an option [1-6]: ' choice
    case "${choice}" in
      1) install_required_packages ;;
      2)
        read -r -p "Output APK [${DEFAULT_OUTPUT}]: " output
        build_apk "${output:-${DEFAULT_OUTPUT}}"
        ;;
      3) show_environment ;;
      4) make -C "${SCRIPT_DIR}" clean ;;
      5) rm -rf -- "${PACKAGE_CACHE}"; echo "Deleted ${PACKAGE_CACHE}" ;;
      6) return ;;
      *) echo "Invalid selection: ${choice}" >&2 ;;
    esac
  done
}

case "${1:-}" in
  -h|--help) usage ;;
  menu) (( $# == 1 )) || { usage >&2; exit 2; }; menu ;;
  install|install-sdk) (( $# == 1 )) || { usage >&2; exit 2; }; install_required_packages ;;
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
