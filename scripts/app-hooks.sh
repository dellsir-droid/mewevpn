# MeWeTail desktop apps (linux / windows / macos) = Electron window (../ui) + the Tailscale daemon and CLI built from source.
# app_prepare is called by scripts/common.sh before electron-builder / dev run, with ELECTRON_OS=linux|windows|mac.
#
# The binaries are compiled from the open-source tailscale.com module at the SAME version the Android app uses (android/go.mod), so
# every platform speaks the same protocol. They are cached in $TOOLS_DIR/tailscale/<os>-<arch>/ and copied to electron/bin/<os>/.
# Needs Go: a system Go (1.21+) is enough, it fetches the exact toolchain itself; otherwise a private Go is downloaded into $TOOLS_DIR/go.

: "${TAILSCALE_ARCH:=}"      # amd64|arm64 (default: this machine; mac: from MACOS_ARCH, --universal builds both and joins them with lipo)
: "${GO_BOOTSTRAP_VERSION:=1.24.7}"
: "${WINTUN_VERSION:=0.14.1}"

ensure_go() {
  [[ -x "$TOOLS_DIR/go/bin/go" ]] && export PATH="$TOOLS_DIR/go/bin:$PATH"
  if have go; then
    local v; v="$(go env GOVERSION 2>/dev/null | sed 's/^go//')"; local minor="${v#*.}"; minor="${minor%%.*}"
    [[ "${v%%.*}" -gt 1 || "${minor:-0}" -ge 21 ]] && return 0
    warn "System Go $v is too old to fetch toolchains (needs 1.21+); using a private Go $GO_BOOTSTRAP_VERSION."
  fi
  local os arch; os="$(uname -s | tr A-Z a-z)"; arch="$(uname -m)"
  case "$arch" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; esac
  case "$os" in linux|darwin) ;; *) err "Install Go from https://go.dev/dl (Windows: winget install GoLang.Go), then run this again."; return 1 ;; esac
  have curl || { err "curl is needed to download Go."; return 1; }
  info "Downloading Go $GO_BOOTSTRAP_VERSION into $TOOLS_DIR/go (no sudo)…"
  rm -rf "$TOOLS_DIR/go"; mkdir -p "$TOOLS_DIR/go"
  curl -fL --retry 3 "https://go.dev/dl/go$GO_BOOTSTRAP_VERSION.$os-$arch.tar.gz" | tar -xz -C "$TOOLS_DIR/go" --strip-components=1 || { err "Go download failed."; return 1; }
  export PATH="$TOOLS_DIR/go/bin:$PATH"; ok "$(go version)"
}

# The tailscale.com version this repo is pinned to (same one the Android app is built with).
tailscale_version() { grep -E '^\s*tailscale\.com\s' "$REPO_DIR/android/go.mod" | head -1 | awk '{print $2}'; }

# build_tailscale GOOS GOARCH OUTDIR : compiles tailscaled + tailscale for that target
build_tailscale() {
  local goos="$1" goarch="$2" out="$3" ver tmp ext=""; [[ "$goos" == windows ]] && ext=".exe"
  ver="$(tailscale_version)"; [[ -n "$ver" ]] || { err "Could not read the tailscale.com version from android/go.mod"; return 1; }
  info "Building tailscaled + tailscale $ver for $goos/$goarch (first time: a few minutes while Go downloads the modules)…"
  tmp="$(mktemp -d)"; mkdir -p "$out"
  ( cd "$tmp" && export GOFLAGS=-mod=mod CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
    && go mod init mewetail-core >/dev/null 2>&1 && go get "tailscale.com@$ver" \
    && go build -trimpath -ldflags "-s -w" -o "$out/tailscaled$ext" tailscale.com/cmd/tailscaled \
    && go build -trimpath -ldflags "-s -w" -o "$out/tailscale$ext" tailscale.com/cmd/tailscale ) \
    || { err "Go build failed."; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

app_prepare() {
  local os="$ELECTRON_OS" goos dirname ext="" arch archs=() a
  case "$os" in mac) goos=darwin; dirname=mac ;; windows) goos=windows; dirname=win; ext=".exe" ;; *) goos=linux; dirname=linux ;; esac
  local host; host="$([[ "$(uname -m)" == aarch64 || "$(uname -m)" == arm64 ]] && echo arm64 || echo amd64)"
  if [[ -n "$TAILSCALE_ARCH" ]]; then archs=("$TAILSCALE_ARCH")
  elif [[ "$os" == mac ]]; then
    case "${MACOS_ARCH:-}" in --universal) archs=(arm64 amd64) ;; --x64) archs=(amd64) ;; --arm64) archs=(arm64) ;; *) archs=("$host") ;; esac
  elif [[ "$os" == windows ]]; then archs=(amd64)
  else archs=("$host"); fi
  ensure_go || return 1
  local bin="$ELECTRON_DIR/bin/$dirname" ver; ver="$(tailscale_version)"
  rm -rf "$bin"; mkdir -p "$bin"
  for a in "${archs[@]}"; do
    local cache="$TOOLS_DIR/tailscale/$ver/$dirname-$a"
    if [[ ! -f "$cache/tailscaled$ext" || ! -f "$cache/tailscale$ext" ]]; then build_tailscale "$goos" "$a" "$cache" || return 1; fi
  done
  if [[ ${#archs[@]} -eq 2 ]]; then          # universal Mac binaries
    have lipo || { err "lipo is needed for a universal build (Xcode command line tools)."; return 1; }
    for b in tailscaled tailscale; do lipo -create -output "$bin/$b" "$TOOLS_DIR/tailscale/$ver/$dirname-arm64/$b" "$TOOLS_DIR/tailscale/$ver/$dirname-amd64/$b"; done
  else
    cp -f "$TOOLS_DIR/tailscale/$ver/$dirname-${archs[0]}/tailscaled$ext" "$TOOLS_DIR/tailscale/$ver/$dirname-${archs[0]}/tailscale$ext" "$bin/"
  fi
  chmod +x "$bin"/* 2>/dev/null
  # Windows also needs the WireGuard TUN driver DLL next to tailscaled.exe.
  if [[ "$os" == windows ]]; then
    local dll="$TOOLS_DIR/tailscale/wintun-$WINTUN_VERSION.dll"
    if [[ ! -f "$dll" ]]; then
      info "Downloading wintun $WINTUN_VERSION…"
      local tmp; tmp="$(mktemp -d)"
      curl -fL --retry 3 -o "$tmp/w.zip" "https://www.wintun.net/builds/wintun-$WINTUN_VERSION.zip" && unzip -q -o "$tmp/w.zip" -d "$tmp" && mkdir -p "$(dirname "$dll")" && cp "$tmp/wintun/bin/amd64/wintun.dll" "$dll" \
        || { rm -rf "$tmp"; err "wintun download failed (https://www.wintun.net)."; return 1; }
      rm -rf "$tmp"
    fi
    cp -f "$dll" "$bin/wintun.dll"
  fi
  # The Linux service installer script travels with the app.
  [[ "$os" == linux ]] && cp -f "$ELECTRON_SRC/linux-install-service.sh" "$bin/" 2>/dev/null
  ok "tailscaled + tailscale ($ver, ${archs[*]}) -> electron/bin/$dirname"
}
