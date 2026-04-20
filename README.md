# RideControl

A macOS menu bar app that maps the buttons on your **Wahoo KICKR Bike** to keyboard shortcuts — so you can control your Mac without leaving the handlebars.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

---

## What it does

The KICKR Bike has 10 buttons across two shifter units — a D-pad on the left, four face buttons (Y/A/B/Z) on the right, and two inside lever buttons. RideControl connects to the bike over Bluetooth and maps each button to a configurable keyboard action or system command.

### Default mapping

| Button | Action |
|--------|--------|
| ↑ Up | Arrow Up |
| ↓ Down | Arrow Down |
| ← Left | Arrow Left |
| → Right | Arrow Right |
| Y (Top) | Tab |
| A (Right) | Return |
| Z (Left) | Cmd + Tab |
| **B (Bottom)** | **Shift modifier (see below)** |
| Left Lever | Fn + Space (Wispr Flow hands-free) |
| Right Lever | Fn hold (Wispr Flow push-to-talk) |

### Shift layer

Hold **B** and press a D-pad button to access a second layer of actions:

| Button | Shifted Action |
|--------|----------------|
| B + ↑ | Screenshot Area |
| B + ↓ | Space |
| B + ← | Backspace |
| B + → | Paste |

All 14 mappings (10 normal + 4 shifted) are fully configurable via the Settings window.

---

## Features

- Connects automatically to any Wahoo KICKR Bike over BLE
- Runs as a lightweight menu bar app — no Dock icon
- Fully remappable buttons via a native macOS Settings window
- Shift layer for 4 extra actions (hold B)
- Launch at login support
- Pin Settings window on top for quick reference while learning the layout
- Reconnects automatically if the bike disconnects
- Zero third-party dependencies — pure Apple frameworks only

### Available actions

Arrow keys, Return, Escape, Tab, Shift+Tab, Cmd+Tab, Space, Backspace, Fn (hold), Fn+Space, Volume Up/Down, Play/Pause, Next/Previous Track, Screenshot Area, Screenshot Full, Copy, Paste.

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
4. Turn on your KICKR Bike — the menu bar will show "Connected" when ready

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

To enable on-screen test buttons for debugging without the bike connected, flip `showTestButtons` to `true` at the top of `RideControlApp.swift`.

---

## How it works

The KICKR Bike exposes its shifter buttons over a proprietary Wahoo BLE characteristic (`A026E03C-0A7D-4AB3-97FA-F1500F9FEB8B`). Each button press sends a 3-byte payload where bytes 1+2 identify the button and byte 3's high nibble indicates press (`≥ 8`) or release (`< 8`).

RideControl subscribes to this characteristic, parses the button events, and injects the mapped keystrokes using `CGEvent`. System commands like screenshots use `screencapture` via `Process`.

### Button payload map

| Button | Byte 1 | Byte 2 |
|--------|--------|--------|
| ↑ Up | `0x02` | `0x00` |
| ↓ Down | `0x04` | `0x00` |
| ← Left | `0x00` | `0x10` |
| → Right | `0x00` | `0x20` |
| Y (Top) | `0x80` | `0x00` |
| A (Right) | `0x00` | `0x80` |
| B (Bottom) | `0x00` | `0x01` |
| Z (Left) | `0x00` | `0x40` |
| Left Lever | `0x20` | `0x00` |
| Right Lever | `0x00` | `0x08` |

---

## License

MIT

### Firmware quirk (KICKR Bike Pro V2)

When the **B** button is held together with **Down**, the bike transmits only
a single BLE packet per press instead of the usual press+release pair, and
the payload looks identical to a release event. RideControl compensates by
firing the shifted action on every Down event while in shift mode, while
treating Up/Left/Right normally (fire on press edge only).

This app was developed and tested against the **KICKR Bike Pro V2**.
Behavior may differ on other KICKR Bike revisions.