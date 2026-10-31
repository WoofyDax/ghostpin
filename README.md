# GhostPin

Change your iPhone's GPS location **from the phone itself** - no computer needed after setup.
Pick a spot on the map, tap **Teleport**, or draw a route and tap **Walk**.

<p align="center">
  <img src="docs/images/app-main.png" width="260" alt="GhostPin main screen">
  <img src="docs/images/app-settings-ondevice.png" width="260" alt="GhostPin settings, On-device mode">
</p>

## Install it (pick one)

| | Best for | Time |
|---|---|---|
| **[Let an AI do it for you](docs/INSTALL_WITH_AI.md)** (recommended) | Everyone. Paste one prompt into Codex or Claude and follow along. | ~20 min |
| **[Step by step by hand](docs/INSTALL_MANUAL.md)** | People who like doing it themselves. | ~30 min |

## What you need
- A Mac (any recent one) with a USB cable for your iPhone, one time
- An iPhone on iOS 17 or newer
- A free Apple ID (no paid developer account needed)
- About 15 GB free for Xcode (free from the Mac App Store)
- **Wi-Fi on the phone whenever you use it.** See "Wi-Fi vs cellular" below.

## How it works (short version)
Apple lets developer tools fake a phone's location. GhostPin does that *on the phone* by talking to the
phone's own developer service through **LocalDevVPN**, a free app that makes a private loop-back tunnel on
the phone. The Mac is only needed for the one-time install and pairing.

## Wi-Fi vs cellular (important)
GhostPin needs the phone to be **connected to a Wi-Fi network** while you use it. The network does **not** need
internet. With Wi-Fi off and only cellular on (we tested on 5G), iOS refuses the connection, because the phone's
developer service only listens when a Wi-Fi-type network exists. Personal Hotspot on the same phone does not help.

If you want to use it away from home on cellular data:
- Carry a **pocket travel router** (or any spare device that makes a Wi-Fi network) with no internet cable plugged in.
  Join its Wi-Fi; your phone keeps using cellular for data. *(Idea based on how iOS works; not yet tested by us.)*
- Or stay on any normal Wi-Fi.

## Good to know
- With a free Apple ID the app **expires after 7 days**. Just run the installer again (`scripts/install.sh`).
- LocalDevVPN must be **Connected** whenever you use GhostPin.
- The fake location lasts only while GhostPin's connection to the phone is open. **Keep GhostPin running**
  (we have not yet tested what happens when iOS suspends it in the background).
- Use this on your own phone, for testing, privacy, or fun. Some apps and games forbid fake locations;
  that is your responsibility.
- Tested on iPhone 17 Pro with iOS 26.7.2. Other devices should work but are not tested.
- Optional extra: `server/` + `run.sh` is a small Mac relay for controlling a USB-connected phone from a web
  page. You do not need it for the normal install.

## Credits and license
MIT licensed (see `LICENSE`). Uses the [idevice](https://github.com/jkcoxson/idevice) library by Jackson Coxson
(MIT), prebuilt in `Native/` from commit `8970209`, and [pymobiledevice3](https://github.com/doronz88/pymobiledevice3)
for the one-time pairing.
