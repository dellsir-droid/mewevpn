#!/usr/bin/env bash
# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly DEFAULT_OUTPUT="${SCRIPT_DIR}/MeWeVPN-debug.apk"

usage() {
  cat <<'EOF'
Build the MeWeVPN debug APK, including the Go networking library.

Usage: ./build-apk.sh [OUTPUT_APK]

OUTPUT_APK defaults to ./MeWeVPN-debug.apk. The Android SDK, NDK, Java, Go,
and other prerequisites described in README.md must already be installed.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if (( $# > 1 )); then
  usage >&2
  exit 2
fi

output="${1:-${DEFAULT_OUTPUT}}"
if [[ "${output}" != /* ]]; then
  output="${PWD}/${output}"
fi

mkdir -p -- "$(dirname -- "${output}")"

echo "Building MeWeVPN APK..."
make -C "${SCRIPT_DIR}" apk

install -m 0644 "${SCRIPT_DIR}/tailscale-debug.apk" "${output}"
echo "MeWeVPN APK written to ${output}"
