#!/bin/sh
# Run as root (pkexec) by the MeWeTail app: installs tailscaled as a systemd service so the VPN works system-wide.
#   linux-install-service.sh <folder with tailscaled + tailscale> <desktop user>
set -e
SRC="${1:?folder with tailscaled and tailscale}"; USER_NAME="${2:-}"
install -m 0755 "$SRC/tailscaled" /usr/local/bin/tailscaled
install -m 0755 "$SRC/tailscale" /usr/local/bin/tailscale
[ -f /etc/default/tailscaled ] || printf 'PORT="41641"\nFLAGS=""\nTS_NO_LOGS_NO_SUPPORT=true\n' > /etc/default/tailscaled   # no log upload to tailscale.com
cat > /etc/systemd/system/tailscaled.service <<'UNIT'
[Unit]
Description=Tailscale node agent
Documentation=https://tailscale.com/kb/
Wants=network-pre.target
After=network-pre.target NetworkManager.service systemd-resolved.service

[Service]
EnvironmentFile=/etc/default/tailscaled
ExecStart=/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=${PORT} $FLAGS
ExecStopPost=/usr/local/bin/tailscaled --cleanup
Restart=on-failure
RuntimeDirectory=tailscale
RuntimeDirectoryMode=0755
StateDirectory=tailscale
StateDirectoryMode=0700
CacheDirectory=tailscale
CacheDirectoryMode=0750
Type=notify

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now tailscaled
# Let the desktop user run `tailscale up` / `down` without sudo.
if [ -n "$USER_NAME" ]; then
  i=0; while [ ! -S /run/tailscale/tailscaled.sock ] && [ $i -lt 20 ]; do sleep 0.5; i=$((i+1)); done
  /usr/local/bin/tailscale set --operator="$USER_NAME" || true
fi
