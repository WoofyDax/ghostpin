#!/usr/bin/env bash
# Starts the relay and (if available) an internet tunnel so the phone can reach it on cellular.
set -e
cd "$(dirname "$0")/server"
[ -d .venv ] || { python3 -m venv .venv && .venv/bin/pip install -q -r requirements.txt; }
PY=.venv/bin/python
echo "Token: $(cat ~/.ghostpin/token 2>/dev/null || echo '(generated on first start)')"
echo "iOS 17+ needs the Apple tunnel daemon in another terminal:  sudo $PWD/$PY -m pymobiledevice3 remote tunneld"
$PY -m uvicorn app:app --host 127.0.0.1 --port 8765 &
SRV=$!; trap 'kill $SRV 2>/dev/null' EXIT
sleep 2; echo "Token: $(cat ~/.ghostpin/token)"
if command -v cloudflared >/dev/null; then
  echo "Public URL appears below (https://*.trycloudflare.com):"
  cloudflared tunnel --url http://127.0.0.1:8765
elif command -v tailscale >/dev/null; then
  tailscale serve --bg 8765 && tailscale serve status
else
  echo "No tunnel tool found. Install one:  brew install cloudflared   (or Tailscale)"; wait $SRV
fi
