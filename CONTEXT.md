# RideControl — Project Context

This file is for AI assistants (Claude Code, etc.) working on this project. It captures the full context of what the app is, how it works, what's been figured out, and the known quirks.

---

## What this app is

RideControl is a macOS menu bar app that maps the buttons on a **Wahoo KICKR Bike Pro V2** to keyboard shortcuts and system actions. The bike has 10 physical buttons across two shifter units, all communicating over Bluetooth Low Energy via a proprietary Wahoo characteristic. The app subscribes to that characteristic, parses button events, and fires the configured action — keystrokes, media keys, screenshots, etc.

It runs as a `LSUIElement` (no Dock icon, menu bar only), persists mappings to `UserDefaults`, and supports launch-at-login via `SMAppService`.

**Author**: Tejs Rasmussen (Tejs on GitHub)
**Repo**: https://github.com/Tejs/ridecontrol
**Hardware target**: KICKR Bike Pro V2 (other revisions untested)
**License**: MIT

---

## Project structure

```
RideControl/
├── RideControl/
│   ├── RideControlApp.swift     ← single-file app, contains everything
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset/  ← cycling icon, blue gradient
│   │   └── MenuBarIcon.imageset/← 20pt PDF, template image
│   └── Info.plist               ← embedded; key settings below
├── RideControl.xcodeproj
├── README.md
├── CONTEXT.md                   ← this file
└── .gitignore
```

### Required Info.plist keys

- `NSBluetoothAlwaysUsageDescription` (String) — usage description, required or app crashes on first BLE call
- `LSUIElement` / `Application is agent (UIElement)` (Boolean YES) — hides Dock icon
- `LSApplicationCategoryType` set to `public.app-category.utilities` (cosmetic only)

### Required entitlements / capabilities

- **Bluetooth** capability (Signing & Capabilities tab) — required for BLE on macOS
- App requires user-granted **Accessibility permission** to inject keystrokes via CGEvent. macOS prompts on first key-injection attempt.

---

## How the bike protocol works

The KICKR Bike exposes shifter button events on a proprietary BLE characteristic:

```
A026E03C-0A7D-4AB3-97FA-F1500F9FEB8B
```

This is one of several `A026...` characteristics under a Wahoo proprietary service. We subscribe via `setNotifyValue(true, ...)` and parse incoming notifications.

### Payload format

Each notification is a 3-byte payload (sometimes longer, but only the first 3 matter):

```
[byte 0] [byte 1] [byte 2]
   |        |        |
   +--------+--------+--- bytes 0+1 identify the button
                          byte 2's high nibble indicates state:
                              ≥ 8  →  pressed
                              < 8  →  released
                          byte 2's low nibble is a rolling sequence counter (ignore)
```

### Button identity table

| Button | Byte 0 | Byte 1 |
|--------|--------|--------|
| Up (D-pad)     | `0x02` | `0x00` |
| Down (D-pad)   | `0x04` | `0x00` |
| Left (D-pad)   | `0x00` | `0x10` |
| Right (D-pad)  | `0x00` | `0x20` |
| Y (top)        | `0x80` | `0x00` |
| A (right)      | `0x00` | `0x80` |
| B (bottom)     | `0x00` | `0x01` |
| Z (left)       | `0x00` | `0x40` |
| Left lever     | `0x20` | `0x00` |
| Right lever    | `0x00` | `0x08` |

### Firmware quirks (KICKR Bike Pro V2)

**B + Down combination is broken**: when the user holds B and presses Down, the bike emits only a single packet per Down press (not a press+release pair like every other combination), and the payload looks like a release event (high nibble < 8). All other combinations (B + Up, B + Left, B + Right) emit normal press+release pairs.

The fix in `handleButton`: in the shift layer (when B is held), Down fires the action on every event regardless of the "pressed" flag, while Up/Left/Right fire only on the press edge. See the `handleButton` method.

---

## App architecture

Everything lives in **`RideControlApp.swift`** as a single file. There's no need to split it — it's intentionally compact. The file contains:

1. **`KeyAction` enum** — every action the app can perform (arrow keys, modifiers, media keys, screenshot, paste/copy, etc.)
2. **`fireAction(_:pressed:)`** — the action dispatcher; takes a `KeyAction` and a press/release flag, posts the appropriate macOS event
3. **`KICKRButton` enum** — the 10 physical buttons with display names
4. **`parseButtonEvent(_:)`** — parses a 3-byte BLE payload into a `ButtonEvent`
5. **`ButtonMappings`** (`@Observable`) — the persistent mapping dictionaries (normal layer + shift layer); saves to `UserDefaults`
6. **`KICKRManager`** (`@Observable`, `CBCentralManagerDelegate`) — BLE connection + button event handling. Tracks `isShiftHeld` state.
7. **`SettingsWindowController`** — manages the standalone settings window (NSWindow, not SwiftUI Settings scene because that's flaky in menu bar apps)
8. **`SettingsView`** — the SwiftUI settings UI with grouped sections, picker rows, pin-on-top button
9. **`RideControlApp`** (`@main`) — the menu bar entry point with `MenuBarExtra`

### Action injection mechanisms

Different actions use different macOS APIs:

- **Standard keys** (arrows, return, escape, tab, space, backspace, V/C with cmd) — `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with `.cgSessionEventTap`
- **Modifier combos** (Shift+Tab, Cmd+Tab, Cmd+V, Cmd+C, Fn+Space) — same `CGEvent` API but with `.flags` set on the event
- **Fn key (hold)** — `CGEvent` with virtualKey `0x3F` and `.maskSecondaryFn` flag
- **Media keys** (Play/Pause, Next, Previous, Volume Up/Down) — `NSEvent.otherEvent(.systemDefined ...)` with subtype 8 and `NX_KEYTYPE_*` constants. **Cannot use CGEvent for these — they'd just type letters.**
- **Screenshots** — spawn `/usr/sbin/screencapture` via `Process()`. CGEvent cannot reliably trigger system screenshot shortcuts. Three variants:
  - `Screenshot Area (Clipboard)` → `screencapture -ic` (interactive area selector, copies PNG to clipboard)
  - `Screenshot Area (File)` → `screencapture -i [path]` (interactive area selector, saves PNG to disk; if `screenshotSaveDir` is set in UserDefaults, a timestamped filename is built into that directory; otherwise no path argument is passed and macOS uses its system-configured default location)
  - `Screenshot Full` → `screencapture -c` (whole screen to clipboard)

### Default mappings

Normal layer:
- ↑ Up → Arrow Up
- ↓ Down → Arrow Down
- ← Left → Arrow Left
- → Right → Arrow Right
- Y (Top) → Tab
- A (Right) → Return
- B (Bottom) → **Shift modifier** (no normal action — used to activate shift layer)
- Z (Left) → Cmd + Tab
- Left Lever → Fn + Space (Wispr Flow hands-free)
- Right Lever → Fn (hold) (Wispr Flow push-to-talk)

Shift layer (hold B + D-pad):
- B + ↑ → Screenshot Area (Clipboard)
- B + ↓ → Space
- B + ← → Backspace
- B + → → Paste

---

## Key code virtual key reference

These are macOS virtual key codes used in `fireAction`:

| Key | Code |
|-----|------|
| Up arrow      | `0x7E` |
| Down arrow    | `0x7D` |
| Left arrow    | `0x7B` |
| Right arrow   | `0x7C` |
| Return        | `0x24` |
| Escape        | `0x35` |
| Tab           | `0x30` |
| Space         | `0x31` |
| Backspace     | `0x33` |
| V             | `0x09` |
| C             | `0x08` |
| 4             | `0x21` |
| Fn            | `0x3F` |

Media keys use these IOKit constants instead:
- `NX_KEYTYPE_SOUND_UP = 0`
- `NX_KEYTYPE_SOUND_DOWN = 1`
- `NX_KEYTYPE_PLAY = 16`
- `NX_KEYTYPE_NEXT = 17`
- `NX_KEYTYPE_PREVIOUS = 18`

---

## Persisted preferences (UserDefaults keys)

| Key | Type | Owner | Purpose |
|-----|------|-------|---------|
| `buttonMappings`      | `[String: String]` | `ButtonMappings` | Normal-layer button → action mapping (raw values) |
| `buttonShiftMappings` | `[String: String]` | `ButtonMappings` | Shift-layer (B + D-pad) mapping (raw values) |
| `screenshotSaveDir`   | `String`           | `SettingsView` (`@AppStorage`) | Optional directory path for `Screenshot Area (File)`. Empty string = use macOS default location. |

**Note on enum rename safety**: `KeyAction` raw values are persisted by string. Renaming a case's raw value will cause stored mappings using the old name to silently fail to decode and fall back to the in-code default. Treat `KeyAction.rawValue` as part of the storage contract.

---

## Debug flag

At the top of `RideControlApp.swift`:

```swift
let showTestButtons = false
```

Set to `true` to show small play (▶) buttons next to each picker row in the settings window. Useful for testing actions when not on the bike. Should be `false` for release builds.

---

## UI conventions

- Settings window is **440pt wide** (locked), with **resizable height**: min 320pt, default 600pt, no max. The window's `contentMaxSize` width and `contentMinSize` width are both pinned to 440 so users can only resize vertically.
- The grouped Form scrolls internally when content exceeds window height — the SwiftUI view no longer uses `.fixedSize`, so the Form fills available vertical space.
- Header: 48pt cycling icon, "RideControl" bold 20pt, "KICKR Bike Controller" subhead in secondary color.
- Pin button (top-right of header): toggles `window.level = .floating` for keep-on-top. Resets to `.normal` when window closes.
- Settings sections: General → Left (D-Pad) → Left — Shift Layer (hold B) → Right (Face Buttons) → Inside Levers.
- General section contains: Launch at login toggle, and Screenshot save location row (path display + Choose…/Reset buttons).
- B button is shown in the Right section as a non-interactive row labeled "Shift Modifier".

---

## Build & deploy

### Running from Xcode (development)

Just hit ▶. The login item registration won't work from Xcode (binary path changes each build), but everything else does.

### Release build (deployment)

1. Product → Archive (with My Mac as destination)
2. In Organizer: Distribute App → Custom → Copy App
3. Save the `.app` to Desktop
4. Drag to `/Applications`
5. First-launch: grant Bluetooth + Accessibility permissions
6. Optionally toggle "Launch at login" in settings

### Permissions checklist

If buttons don't fire keystrokes:
- System Settings → Privacy & Security → Accessibility → ensure RideControl is listed and enabled
- Restart the app after granting

If the bike never connects:
- System Settings → Privacy & Security → Bluetooth → ensure RideControl is listed and enabled
- Bike must be powered on and within range
- Check `system_profiler SPBluetoothDataType` to verify the Mac sees the bike at OS level

---

## Dependencies

**None.** Pure Apple frameworks only:
- SwiftUI, AppKit (UI)
- CoreBluetooth (BLE)
- CoreGraphics (CGEvent)
- ServiceManagement (login items)
- UserNotifications (imported but unused — can be removed if cleaning up)
- Foundation (UserDefaults)

This is intentional — keeps the supply chain trivial, security-clean, and the app footprint near zero (~15-20MB RAM idle).

---

## Common follow-up tasks

If asked to add a new action, the pattern is:
1. Add a case to `KeyAction` enum with a display name
2. Add a `case` to `fireAction`'s switch statement with the appropriate event posting
3. Optionally set it as a default in `ButtonMappings.map` or `shiftMap`

If asked to change a default mapping, edit `ButtonMappings.map` or `ButtonMappings.shiftMap` (note: existing users have stored mappings in UserDefaults that will override defaults — only new installs get the new default).

If asked to add a new layer or modifier button, the shift logic is in `KICKRManager.handleButton`. Currently only B is treated as a modifier. Adding more would require additional state tracking.

---

## History / context this came from

This project was bootstrapped in a single chat session through reverse-engineering the KICKR Bike's BLE protocol from scratch. There was no public documentation for the shifter button characteristic — it was discovered by building a CoreBluetooth sniffer (`KICKRSniffer`, an earlier prototype) that subscribed to all notifiable characteristics, then pressing each button while logging hex dumps. The sniffer code isn't in this repo — only the production app.
