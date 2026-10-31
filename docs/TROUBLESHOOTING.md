# Troubleshooting

| Problem | Fix |
|---|---|
| Installer: "No iPhone found" | Unlock the phone, replug the cable, tap **Trust**. Try another cable or port. |
| "Turn on Developer Mode" | iPhone Settings > Privacy & Security > Developer Mode > On > restart. |
| "No Apple developer team found" | Sign in with your Apple ID in Xcode > Settings > Accounts, open `GhostPin.xcodeproj`, choose a Team under Signing & Capabilities. |
| App will not open ("untrusted developer") | iPhone Settings > General > VPN & Device Management > your Apple ID > Trust. |
| App stopped opening after about a week | Free-account expiry. Re-run `scripts/install.sh` with the phone plugged in. |
| GhostPin error mentioning "Connect" / "Connection reset" | Open LocalDevVPN and make sure it says **Connected**, then retry. Re-run the installer if it persists (it re-creates the pairing file). |
| Works on Wi-Fi but fails on cellular ("Connection refused") | Expected: iOS needs a Wi-Fi network (internet not required). Join any Wi-Fi, or a travel router with no internet. Personal Hotspot on the same phone does not work. |
| Location went back to normal after switching apps | The fake location only lasts while GhostPin stays connected. Reopen GhostPin and Teleport again. |
| Maps still shows the real location | Tap **Teleport** again; close and reopen Maps. |
| Want your real location back | In GhostPin tap **Reset GPS** (or restart the phone). |

The app writes a debug log to `Documents/idevice.log` inside the app; an AI helper can copy it with
`xcrun devicectl device copy from` to see what failed.
