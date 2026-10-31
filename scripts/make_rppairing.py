#!/usr/bin/env python3
"""Turn the Mac's trusted RemotePairing record into the file GhostPin needs on the phone.
Usage: make_rppairing.py <UDID> <output.plist>
Private key material: keep the output private; never commit or share it."""
import plistlib, platform, sys, uuid
from pathlib import Path

udid, out = sys.argv[1], sys.argv[2]
src_path = Path.home() / ".pymobiledevice3" / f"remote_{udid}.plist"
if not src_path.exists():
    sys.exit(f"No remote pairing record at {src_path}. Run the tunnel step first.")
src = plistlib.loads(src_path.read_bytes())
dst = {
    "public_key": src["public_key"],
    "private_key": src["private_key"],
    "identifier": str(uuid.uuid3(uuid.NAMESPACE_DNS, platform.node())).upper(),
}
if src.get("peer_alt_irk"):
    dst["alt_irk"] = src["peer_alt_irk"]
Path(out).write_bytes(plistlib.dumps(dst))
Path(out).chmod(0o600)
print("wrote", out)
