#!/usr/bin/env bash
# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

if (( $# != 2 )); then
  echo "usage: $0 EXPECTED_SHA256 FILE" >&2
  exit 2
fi

if command -v sha256sum >/dev/null 2>&1; then
  printf '%s  %s\n' "$1" "$2" | sha256sum --check -
elif command -v shasum >/dev/null 2>&1; then
  printf '%s  %s\n' "$1" "$2" | shasum --algorithm 256 --check -
else
  echo "sha256sum or shasum is required to verify downloads." >&2
  exit 1
fi
