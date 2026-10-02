# Shared helpers for the per-platform build menus (linux/, windows/, ios/). Sourced, not run.
# Needs before sourcing: ROOT_DIR (the platform folder), and the caller's own menu.

REPO_DIR="$(cd "$ROOT_DIR/.." && pwd -P)"
# shellcheck source=app.conf
source "$REPO_DIR/scripts/app.conf"
# Optional per-app hooks (scripts/app-hooks.sh): app_prepare runs before packaging (e.g. fetch a helper binary for $ELECTRON_OS).
[[ -f "$REPO_DIR/scripts/app-hooks.sh" ]] && source "$REPO_DIR/scripts/app-hooks.sh"
WEB_DIR="${UI_DIR:+$REPO_DIR/$UI_DIR}"  # the app's own UI, one copy for every platform (empty when the app just opens a site)
ELECTRON_SRC="$REPO_DIR/electron"       # the desktop shell's source, shared by linux/, windows/ and macos/ (in git)
ELECTRON_DIR="$ELECTRON_SRC"            # where it is built; on the Mac that is under the tools folder (set below), so node_modules etc. live there
# The shared folders are mounted at /sharedfolders on the Linux machines; on the Mac they are the SMB share below.
if [[ "$(uname -s)" == "Darwin" ]]; then : "${SHARED_ROOT:=/Users/dellsir/SMB/k8snas001_sharedfolders}"; else : "${SHARED_ROOT:=/sharedfolders}"; fi
: "${ICON_SRC:=$SHARED_ROOT/media/content/icons/mewe/$ICON_NAME}"
: "${SYNC_ROOT:=$SHARED_ROOT/sync_p/software}"
: "${NODE_VERSION:=22.11.0}"
# Where downloaded tools live (private Node.js, npm/Electron caches, XcodeGen, helper binaries). On the Mac they all go to
# /Users/dellsir/Documents/31_macos/bin/<ios|macos>/ (each menu sets TOOLS_PLATFORM); elsewhere into <repo>/.tools/.
: "${TOOLS_PLATFORM:=${ELECTRON_OS:-tools}}"
if [[ "$(uname -s)" == "Darwin" ]]; then
  : "${TOOLS_ROOT:=/Users/dellsir/Documents/31_macos/bin}"; TOOLS_DIR="${TOOLS_DIR:-$TOOLS_ROOT/$TOOLS_PLATFORM}"
  mkdir -p "$TOOLS_DIR" 2>/dev/null
  export npm_config_cache="${npm_config_cache:-$TOOLS_DIR/npm-cache}" ELECTRON_CACHE="${ELECTRON_CACHE:-$TOOLS_DIR/electron-cache}" ELECTRON_BUILDER_CACHE="${ELECTRON_BUILDER_CACHE:-$TOOLS_DIR/electron-builder-cache}"
else
  TOOLS_DIR="${TOOLS_DIR:-$REPO_DIR/.tools}"
fi
: "${NODE_DIR:=$TOOLS_DIR/node}"        # private Node.js, downloaded on demand (no sudo)
# npm cannot keep node_modules anywhere but next to package.json, so on the Mac the shell is built from a copy under the tools folder.
[[ "$(uname -s)" == "Darwin" ]] && ELECTRON_DIR="$TOOLS_DIR/electron/$APP_SLUG"
[[ -d "$TOOLS_DIR/xcodegen/xcodegen/bin" ]] && export PATH="$TOOLS_DIR/xcodegen/xcodegen/bin:$PATH"
# XcodeGen (iOS project generator) as a plain download into $TOOLS_DIR — no Homebrew needed.
ensure_xcodegen() {
  command -v xcodegen >/dev/null 2>&1 && return 0
  info "Downloading XcodeGen into $TOOLS_DIR/xcodegen …"
  local tmp; tmp="$(mktemp -d)"
  curl -fL --retry 3 -o "$tmp/x.zip" https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip \
    && mkdir -p "$TOOLS_DIR/xcodegen" && rm -rf "$TOOLS_DIR/xcodegen/xcodegen" && unzip -q -o "$tmp/x.zip" -d "$TOOLS_DIR/xcodegen" || { rm -rf "$tmp"; err "XcodeGen download failed."; return 1; }
  rm -rf "$tmp"; export PATH="$TOOLS_DIR/xcodegen/xcodegen/bin:$PATH"; ok "XcodeGen $(xcodegen --version 2>/dev/null)"
}

BOLD=$'\033[1m'; RESET=$'\033[0m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'
info()  { printf '%s[*]%s %s\n' "$CYAN" "$RESET" "$*"; }
ok()    { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$YELLOW" "$RESET" "$*"; }
err()   { printf '%s[error]%s %s\n' "$RED" "$RESET" "$*" >&2; }
header(){ printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }
have()  { command -v "$1" >/dev/null 2>&1; }
confirm() { local r; read -r -p "$1 [y/N] " r; [[ "$r" =~ ^([yY][eE][sS]|[yY])$ ]]; }

# ---- Node.js (for the Electron desktop apps) -------------------------------------------------------------------------------
use_private_node() { [[ -x "$NODE_DIR/bin/node" ]] && export PATH="$NODE_DIR/bin:$PATH"; }
ensure_node() {
  use_private_node
  # Electron's tooling is only tested on LTS Node: accept 18-24, otherwise (e.g. a brand-new Node 26) use a private LTS copy.
  if have node && have npm; then
    local major; major="$(node -p 'process.versions.node.split(".")[0]')"
    [[ "$major" -ge 18 && "$major" -le 24 ]] && return 0
    warn "System Node.js $(node -v) is outside 18-24 (what Electron's build tools support); using a private Node.js $NODE_VERSION."
  fi
  local os arch pkg; os="$(uname -s)"; arch="$(uname -m)"
  case "$os-$arch" in
    Linux-x86_64)  pkg="linux-x64" ;;
    Linux-aarch64) pkg="linux-arm64" ;;
    Darwin-arm64)  pkg="darwin-arm64" ;;
    Darwin-x86_64) pkg="darwin-x64" ;;
    *) err "Install Node.js 20-24 from https://nodejs.org (Windows: winget install OpenJS.NodeJS.LTS), then run this again."; return 1 ;;
  esac
  info "Downloading Node.js $NODE_VERSION into $NODE_DIR (no sudo)…"
  have curl || { err "curl is needed to download Node.js."; return 1; }
  rm -rf "$NODE_DIR"; mkdir -p "$NODE_DIR" && curl -fL "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-$pkg.tar.gz" | tar -xz -C "$NODE_DIR" --strip-components=1 \
    || { err "Node.js download failed."; return 1; }
  export PATH="$NODE_DIR/bin:$PATH"; ok "Node.js $(node -v)"
}

# export_to DIR FILE... : copy results to DIR (normally the shared folder). A share that is missing or read-only is a warning, not a failure.
export_to() {
  local dir="$1"; shift
  local f n=0 out
  mkdir -p "$dir" 2>/dev/null
  for f in "$@"; do
    [[ -e "$f" ]] || continue
    # No writability pre-check: `test -w` is unreliable on SMB shares (it can say "no" for a folder you can write to), so just try and show the real error.
    if out="$(cp -R "$f" "$dir/" 2>&1)"; then n=$((n+1)); ok "$(basename "$f") -> $dir"
    else warn "Could not copy $(basename "$f") to $dir: ${out:-unknown error}"; fi
  done
  [[ $n -gt 0 ]] || warn "Nothing was copied to $dir. The build is still in: $(dirname "${1:-$dir}")"
}

# ---- icons -------------------------------------------------------------------------------------------------------------
convert_bin() { if have magick; then echo magick; elif have convert; then echo convert; fi; }
# Without ImageMagick the bundled icon (design/mewetail.png, drawn by scripts/gen-icons.js) is rendered straight at each size with Node.
need_icon_tools() {
  [[ -n "$(convert_bin)" ]] && return 0
  have node && return 0
  err "ImageMagick (apt install imagemagick / brew install imagemagick) or Node.js is needed to make icons."; return 1
}
# ask_default VAR "Prompt": shows the current value (the default); Enter keeps it, typing replaces it. Silent when not on a terminal
# (non-interactive runs like ./build.sh 2 3 piped or from cron keep the defaults).
ask_default() {
  local var="$1" cur v; cur="${!var}"
  [[ -t 0 ]] || return 0
  read -r -p "$2 [$cur]: " v
  [[ -n "$v" ]] && printf -v "$var" '%s' "${v/#\~/$HOME}"
  return 0
}
find_icon_src() {
  ask_default ICON_SRC "Icon PNG (square)"
  local src="$ICON_SRC"
  if [[ ! -f "$src" ]]; then
    if [[ -f "$REPO_DIR/design/$ICON_NAME" ]]; then warn "Icon source not found: $src — using the bundled $REPO_DIR/design/$ICON_NAME"; src="$REPO_DIR/design/$ICON_NAME"
    else warn "Icon source not found: $src"; read -r -p "Path to a square PNG: " src; [[ -f "$src" ]] || { err "File not found: $src"; return 1; }; fi
  fi
  ICON_FOUND="$src"
}
# resize_icon SRC SIZE OUT  — square, transparent background kept
resize_icon() {
  if [[ -n "$(convert_bin)" ]]; then "$(convert_bin)" -background none "$1" -resize "${2}x${2}^" -gravity center -extent "${2}x${2}" "$3"
  else node "$REPO_DIR/scripts/gen-icons.js" png "$2" "$3"; fi    # bundled icon only (see need_icon_tools)
}
# The in-game header icon is the same art as the launcher icon, shared by every platform.
make_web_icon() { [[ -n "$WEB_DIR" ]] || return 0; mkdir -p "$WEB_DIR/img" && resize_icon "$1" 192 "$WEB_DIR/img/app-icon.png" && ok "In-game icon -> $UI_DIR/img/app-icon.png"; }

APP_VERSION="${APP_VERSION:-1.0.0}"
result_name() { echo "$APP_NAME-$APP_VERSION.$1"; }     # the one naming rule for finished apps: MeWeMath-1.0.0.dmg
APP_PROJECT="${APP_NAME//[^A-Za-z0-9]/}"      # Xcode project / scheme name
APP_IOS_ID="${APP_IOS_ID:-$APP_ID}"          # iOS bundle id (defaults to APP_ID)
export APP_VERSION APP_IOS_ID APP_PROJECT APP_NAME APP_SLUG APP_ID APP_SCHEME APP_DESC LINUX_CATEGORY MAC_CATEGORY START_URL FALLBACK_URL OIDC_CLIENT AUTH_GLOBAL NATIVE_CONFIG

# ---- Electron desktop build (linux/, windows/) ---------------------------------------------------------------------------
# electron_prepare: private Node if needed, the game copied next to the shell, dependencies installed.
electron_prepare() {
  ensure_node || return 1
  if [[ "$ELECTRON_DIR" != "$ELECTRON_SRC" ]]; then   # refresh the build copy from the repo (keeps node_modules, build/, bin/, stage/)
    mkdir -p "$ELECTRON_DIR" && cp -R "$ELECTRON_SRC/." "$ELECTRON_DIR/" || return 1
    rm -rf "$ELECTRON_DIR/.git"
  fi
  rm -rf "$ELECTRON_DIR/www" && mkdir -p "$ELECTRON_DIR/www"
  [[ -n "$WEB_DIR" ]] && { cp -r "$WEB_DIR/." "$ELECTRON_DIR/www/" || return 1; }
  # app.config.json (what this app is) -> package.json (what electron-builder needs)
  (cd "$ELECTRON_DIR" && node make-package.js) || { err "Could not write electron/package.json"; return 1; }
  if declare -F app_prepare >/dev/null; then app_prepare || return 1; fi
  # A half-finished or other-Node install (missing app-builder-bin etc.) is wiped and redone.
  if ! (cd "$ELECTRON_DIR" && [[ -d node_modules/electron && -d node_modules/app-builder-bin ]] && npx --no-install electron-builder --version >/dev/null 2>&1); then
    info "Installing Electron (npm install, one-off, a few minutes)…"
    rm -rf "$ELECTRON_DIR/node_modules" "$ELECTRON_DIR/package-lock.json"
    (cd "$ELECTRON_DIR" && npm install --no-audit --no-fund) || { err "npm install failed."; return 1; }
  fi
}
# electron_icons_png OUT_DIR — build/icon.png (512) for electron-builder
electron_icon_png() {
  mkdir -p "$ELECTRON_DIR/build"
  if [[ -f "$ICON_SRC" ]] && [[ -n "$(convert_bin)" ]]; then resize_icon "$ICON_SRC" 512 "$ELECTRON_DIR/build/icon.png"
  elif have node; then node "$REPO_DIR/scripts/gen-icons.js" png 512 "$ELECTRON_DIR/build/icon.png"
  elif [[ -f "$WEB_DIR/img/app-icon.png" ]]; then cp "$WEB_DIR/img/app-icon.png" "$ELECTRON_DIR/build/icon.png"; fi
}
# electron-builder leaves the unpacked app next to the packages (dist/mac-universal/X.app, dist/win-unpacked, ...). Spotlight and Launchpad list a
# second copy of the app from there, so remove those folders once the real packages exist; and keep the Mac's tools folder out of Spotlight.
electron_tidy_dist() {
  rm -rf "$ELECTRON_DIR"/dist/mac "$ELECTRON_DIR"/dist/mac-* "$ELECTRON_DIR"/dist/*-unpacked
  [[ "$(uname -s)" == "Darwin" && -d "$TOOLS_DIR" ]] && : > "$TOOLS_DIR/.metadata_never_index"
  return 0
}
electron_run_dev() { electron_prepare && (cd "$ELECTRON_DIR" && npx electron . --no-sandbox); }
electron_clean() { rm -rf "$ELECTRON_DIR/www" "$ELECTRON_DIR/dist" "$ELECTRON_DIR/build" "$ELECTRON_DIR/package.json" "$ELECTRON_DIR/app.config.json"; ok "Cleaned electron/www, dist, build."; }
electron_remove_modules() { confirm "Delete electron/node_modules and the downloaded tools in $TOOLS_DIR (Node.js, caches)?" && rm -rf "$ELECTRON_DIR/node_modules" "$TOOLS_DIR" && ok "Deleted."; }

# ---- menu runner ---------------------------------------------------------------------------------------------------------
# run_menu print_fn choice_fn "$@"   (non-interactive: ./build.sh 1 3)
run_menu() {
  local print_fn="$1" choice_fn="$2"; shift 2
  if [[ $# -gt 0 ]]; then for a in "$@"; do "$choice_fn" "$a" || exit 0; done; exit 0; fi
  while true; do
    "$print_fn"; read -r -p "Choose an option: " c
    "$choice_fn" "$c" || break
    printf '\nPress Enter to continue...'; read -r _
  done
  info "Goodbye!"
}
