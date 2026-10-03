# MeWeTail

A Tailscale-compatible private-network client for MeWe devices, based on the open-source [Tailscale](https://github.com/tailscale/tailscale)
code. Default control server **https://hs.m-we.org** (Headscale); sign-in goes through the server's OIDC to **https://oidc.m-we.org**
(realm `mwe`), so the same account works across every `mewe*` app. The server can be changed in each app.

## One folder per platform (each has its own `build.sh` menu)

| Folder | What it is | Output |
|---|---|---|
| `android/` | Tailscale Android client (Kotlin + Go), rebranded, default server hs.m-we.org; built in Docker | `MeWeTail-<ver>.apk` |
| `ios/` | SwiftUI app (XcodeGen), sets the server + OIDC sign-in; Mac + Xcode | simulator `.zip`, signed `.ipa` |
| `macos/` | Electron window + `tailscaled`/`tailscale` built from source; run on a Mac | `.dmg`, `.zip` |
| `linux/` | same Electron app | AppImage, `.deb`, `.tar.gz` |
| `windows/` | same Electron app (+ wintun) | portable `.zip`, Setup `.exe` |

Shared: `electron/` (desktop shell), `ui/` (desktop window), `scripts/` (`app.conf` = what this app is, `common.sh` = helpers),
`design/mewetail.png` (icon source; override with `ICON_SRC=/path.png`).

Android builds in Docker when it is installed (upstream's reproducible toolchain), otherwise with a local JDK + Android SDK/NDK + Go (`USE_DOCKER=0 android/build.sh 1 3`).

Run `./<os>/build.sh` for the menu, or pass options non-interactively, e.g. `android/build.sh 1 3`.
Results are copied to `$SYNC_ROOT/<os>/mewe` (default `/sharedfolders/sync_p/software`).

## iOS note
A system-wide VPN on iOS requires a Network Extension built on Tailscale's iOS core, which is not part of the open-source release.
`ios/` therefore configures the server and signs in via oidc.m-we.org, and hands over to the official Tailscale app
(Settings -> Use alternate server -> `https://hs.m-we.org`). It was not compiled in the authoring environment (needs macOS/Xcode).
