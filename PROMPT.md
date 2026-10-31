# The prompt

Copy everything inside the box and paste it into Codex or Claude (with full-access / bypass permissions).

```text
You are installing GhostPin (an iPhone location-spoofing app) on my iPhone from my Mac. I am not technical,
so do the work yourself and talk to me in plain language. Only stop to ask me when a physical action on my
phone or a Mac password is needed.

1. Run: git clone https://github.com/WoofyDax/ghostpin.git ~/GhostPin && cd ~/GhostPin   (if it already exists, run git pull instead).
2. Read README.md, docs/INSTALL_MANUAL.md and scripts/install.sh so you know the plan.
3. Check my setup and fix what you can yourself: Xcode installed and opened once with the license accepted
   (if Xcode is missing, tell me to install it free from the Mac App Store and wait), my iPhone is plugged in
   and unlocked (`xcrun devicectl list devices`).
4. Run scripts/install.sh and keep re-running it after fixing each problem it reports. When it needs me, tell me
   exactly what to tap, one step at a time. Expect to need me for: tapping "Trust" on the phone, turning on
   Developer Mode (Settings > Privacy & Security), my Mac password (it is typed invisibly, tell me that),
   signing into Xcode with my Apple ID (Xcode > Settings > Accounts), trusting the developer app on the phone
   (Settings > General > VPN & Device Management), and installing the free LocalDevVPN app from the App Store
   and tapping Connect.
5. When the install works, ask me to open GhostPin, set Settings > Mode to On-device, search for a place and tap
   Teleport. Confirm it worked with me. Then tell me to tap Reset GPS to go back to my real location.
6. Safety rules: never upload, print, email or commit the files in ~/.ghostpin or ~/.pymobiledevice3 (they are
   private keys). Do not change any Mac or iPhone setting that this guide does not mention. Do not delete anything.
7. If something fails twice, read the error, look at docs/TROUBLESHOOTING.md, and try a different fix. Finish with
   a short summary of what you did and the reminder that I must re-run scripts/install.sh every 7 days.
```
