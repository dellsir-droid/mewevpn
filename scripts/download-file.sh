#!/usr/bin/env bash
# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

# Download a file reliably on slow or unstable links. Each retry is a new curl invocation because
# curl's built-in --retry restarts an interrupted transfer instead of consistently resuming it.

set -euo pipefail

if (( $# != 2 )); then
  echo "usage: $0 URL OUTPUT" >&2
  exit 2
fi

readonly url="$1"
readonly output="$2"
readonly max_attempts="${DOWNLOAD_MAX_ATTEMPTS:-100}"
readonly retry_delay="${DOWNLOAD_RETRY_DELAY:-5}"

if [[ ! "${max_attempts}" =~ ^[1-9][0-9]*$ || ! "${retry_delay}" =~ ^[0-9]+$ ]]; then
  echo "DOWNLOAD_MAX_ATTEMPTS must be positive and DOWNLOAD_RETRY_DELAY non-negative." >&2
  exit 2
fi

mkdir -p -- "$(dirname -- "${output}")"

for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  echo "Download attempt ${attempt}/${max_attempts}: ${url}"
  if curl --http1.1 \
      --fail --location \
      --continue-at - \
      --connect-timeout 30 \
      --speed-limit 1024 --speed-time 120 \
      --output "${output}" \
      "${url}"; then
    exit 0
  fi

  if (( attempt < max_attempts )); then
    size="$(wc -c <"${output}" 2>/dev/null || printf '0')"
    echo "Transfer interrupted at ${size} bytes; resuming in ${retry_delay}s..." >&2
    sleep "${retry_delay}"
  fi
done

echo "Download failed after ${max_attempts} attempts; partial file retained at ${output}." >&2
exit 1
