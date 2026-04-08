# RideControl

A macOS menu bar app that maps the buttons on your **Wahoo KICKR Bike** to keyboard shortcuts — so you can control your Mac without leaving the handlebars.

![RideControl menu bar app](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

---

## What it does

The KICKR Bike has 10 buttons across two shifter units — a D-pad, four face buttons (Y/A/B/Z), and two inside lever buttons. RideControl connects to the bike over Bluetooth and maps each button to a configurable keyboard action.

Default mapping:

| Button | Action |
|--------|--------|
| ↑ Up | Arrow Up |
| ↓ Down | Arrow Down |
| ← Left | Arrow Left |
| → Right | Arrow Right |
| Y △ | Tab |
| B ✕ | Shift + Tab |
| A ○ | Return |
| Z □ | Cmd + Tab |
| Left Lever | Fn + Space (Wispr Flow hands-free) |
| Right Lever | Fn hold (Wispr Flow push-to-talk) |

All mappings are fully configurable via the Settings window.

---

## Features

- Connects automatically to any Wahoo KICKR Bike over BLE
- Runs as a lightweight menu bar app — no Dock icon
- Fully remappable buttons via a native macOS Settings window
- Launch at login support
- Reconnects automatically if the bike disconnects
- Zero third-party dependencies — pure Apple frameworks only

---

## Requirements

- macOS 13 or later
- Wahoo KICKR Bike (any version with shifter buttons)
- Accessibility permission (for keyboard injection)
- Bluetooth permission

---

## Installation

1. Download the latest release from the [Releases](../../releases) page
2. Move `RideControl.app` to your `/Applications` folder
3. Open it — grant Bluetooth and Accessibility permissions when prompted
4. Turn on your KICKR Bike — the menu bar icon will fill in when connected

To enable launch at login: click the menu bar icon → Settings → toggle **Launch at login**

---

## Building from source

Requires Xcode 15+.

```bash
git clone https://github.com/Tejs/ridecontrol.git
cd ridecontrol
open RideControl.xcodeproj
```

Hit ▶ in Xcode. Grant Bluetooth and Accessibility permissions on first run.

---

## How it works

The KICKR Bike exposes its shifter buttons over a proprietary Wahoo BLE characteristic (`A026E03C-0A7D-4AB3-97FA-F1500F9FEB8B`). Each button press sends a 3-byte payload where bytes 1+2 identify the button and byte 3's high nibble indicates press (`≥ 8`) or release (`< 8`).

RideControl subscribes to this characteristic, parses the button events, and injects the mapped keystrokes using `CGEvent`.

---

## Button payload map

| Button | Byte 1 | Byte 2 |
|--------|--------|--------|
| ↑ Up | `0x02` | `0x00` |
| ↓ Down | `0x04` | `0x00` |
| ← Left | `0x00` | `0x10` |
| → Right | `0x00` | `0x20` |
| Y △ | `0x80` | `0x00` |
| A ○ | `0x00` | `0x80` |
| B ✕ | `0x00` | `0x01` |
| Z □ | `0x00` | `0x40` |
| Left Lever | `0x20` | `0x00` |
| Right Lever | `0x00` | `0x08` |

---

## License

MIT
