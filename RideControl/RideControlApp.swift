import SwiftUI
import CoreBluetooth
import CoreGraphics
import AppKit
import ServiceManagement
import UserNotifications

// MARK: - Debug flags

let showTestButtons = false

// MARK: - UserDefaults keys

let screenshotDirKey = "screenshotSaveDir"

// MARK: - Actions

enum KeyAction: String, CaseIterable, Codable {
    case arrowUp        = "Arrow Up"
    case arrowDown      = "Arrow Down"
    case arrowLeft      = "Arrow Left"
    case arrowRight     = "Arrow Right"
    case returnKey      = "Return"
    case escape         = "Escape"
    case tab            = "Tab"
    case shiftTab       = "Shift + Tab"
    case cmdTab         = "Cmd + Tab"
    case space          = "Space"
    case backspace      = "Backspace"
    case fn             = "Fn (hold)"
    case fnSpace        = "Fn + Space"
    case volumeUp       = "Volume Up"
    case volumeDown     = "Volume Down"
    case mediaPlay      = "Play/Pause"
    case mediaNext      = "Next Track"
    case mediaPrev      = "Previous Track"
    case screenshotArea     = "Screenshot Area (Clipboard)"
    case screenshotAreaFile = "Screenshot Area (File)"
    case screenshotFull     = "Screenshot Full"
    case paste          = "Paste"
    case copy           = "Copy"
    case none           = "None"
}

// Media key constants from IOKit hidsystem/ev_keymap.h
private let NX_KEYTYPE_SOUND_UP: Int32   = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
private let NX_KEYTYPE_PLAY: Int32       = 16
private let NX_KEYTYPE_NEXT: Int32       = 17
private let NX_KEYTYPE_PREVIOUS: Int32   = 18

private func postMediaKey(_ key: Int32) {
    func send(down: Bool) {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(down ? 0xA00 : 0xB00))
        let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
    send(down: true)
    send(down: false)
}

func fireAction(_ action: KeyAction, pressed: Bool) {
    let src = CGEventSource(stateID: .hidSystemState)
    func key(_ code: CGKeyCode, down: Bool) {
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)?.post(tap: .cgSessionEventTap)
    }
    func tap(_ code: CGKeyCode) { key(code, down: true); key(code, down: false) }
    switch action {
    case .arrowUp    where pressed: tap(0x7E)
    case .arrowDown  where pressed: tap(0x7D)
    case .arrowLeft  where pressed: tap(0x7B)
    case .arrowRight where pressed: tap(0x7C)
    case .returnKey  where pressed: tap(0x24)
    case .escape     where pressed: tap(0x35)
    case .tab        where pressed: tap(0x30)
    case .space      where pressed: tap(0x31)
    case .backspace  where pressed: tap(0x33)
    case .volumeUp   where pressed: postMediaKey(NX_KEYTYPE_SOUND_UP)
    case .volumeDown where pressed: postMediaKey(NX_KEYTYPE_SOUND_DOWN)
    case .mediaPlay  where pressed: postMediaKey(NX_KEYTYPE_PLAY)
    case .mediaNext  where pressed: postMediaKey(NX_KEYTYPE_NEXT)
    case .mediaPrev  where pressed: postMediaKey(NX_KEYTYPE_PREVIOUS)
    case .fn:
        let e = CGEvent(keyboardEventSource: src, virtualKey: 0x3F, keyDown: pressed)
        e?.flags = pressed ? [.maskSecondaryFn] : []
        e?.post(tap: .cgSessionEventTap)
    case .fnSpace where pressed:
        let fnD = CGEvent(keyboardEventSource: src, virtualKey: 0x3F, keyDown: true)
        fnD?.flags = .maskSecondaryFn; fnD?.post(tap: .cgSessionEventTap)
        let spD = CGEvent(keyboardEventSource: src, virtualKey: 0x31, keyDown: true)
        spD?.flags = .maskSecondaryFn; spD?.post(tap: .cgSessionEventTap)
        let spU = CGEvent(keyboardEventSource: src, virtualKey: 0x31, keyDown: false)
        spU?.flags = .maskSecondaryFn; spU?.post(tap: .cgSessionEventTap)
        let fnU = CGEvent(keyboardEventSource: src, virtualKey: 0x3F, keyDown: false)
        fnU?.post(tap: .cgSessionEventTap)
    case .shiftTab where pressed:
        let e = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: true)
        e?.flags = .maskShift
        e?.post(tap: .cgSessionEventTap)
        let u = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: false)
        u?.post(tap: .cgSessionEventTap)
    case .cmdTab where pressed:
        let e = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: true)
        e?.flags = .maskCommand
        e?.post(tap: .cgSessionEventTap)
        let u = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: false)
        u?.flags = .maskCommand
        u?.post(tap: .cgSessionEventTap)
    case .screenshotArea where pressed:
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-ic"]
        task.launch()
    case .screenshotAreaFile where pressed:
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        if let dir = UserDefaults.standard.string(forKey: screenshotDirKey), !dir.isEmpty {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let path = (dir as NSString).appendingPathComponent("Screenshot \(fmt.string(from: Date())).png")
            task.arguments = ["-i", path]
        } else {
            task.arguments = ["-i"]
        }
        task.launch()
    case .screenshotFull where pressed:
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-c"]
        task.launch()
    case .paste where pressed:
        let e = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        e?.flags = .maskCommand
        e?.post(tap: .cgSessionEventTap)
        let u = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        u?.post(tap: .cgSessionEventTap)
    case .copy where pressed:
        let e = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        e?.flags = .maskCommand
        e?.post(tap: .cgSessionEventTap)
        let u = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        u?.post(tap: .cgSessionEventTap)
    default: break
    }
}

// MARK: - Button Map

enum KICKRButton: String, CaseIterable {
    case up           = "↑ Up"
    case down         = "↓ Down"
    case left         = "← Left"
    case right        = "→ Right"
    case y            = "Y (Top)"
    case b            = "B (Bottom)"
    case a            = "A (Right)"
    case z            = "Z (Left)"
    case leftInside   = "Left Lever"
    case rightInside  = "Right Lever"
}

struct ButtonEvent {
    let button: KICKRButton
    let pressed: Bool
}

func parseButtonEvent(_ data: Data) -> ButtonEvent? {
    guard data.count >= 3 else { return nil }
    let pressed = (data[2] >> 4) >= 8
    let button: KICKRButton? = switch (data[0], data[1]) {
        case (0x02, 0x00): .up
        case (0x04, 0x00): .down
        case (0x00, 0x10): .left
        case (0x00, 0x20): .right
        case (0x20, 0x00): .leftInside
        case (0x00, 0x08): .rightInside
        case (0x80, 0x00): .y
        case (0x00, 0x80): .a
        case (0x00, 0x01): .b
        case (0x00, 0x40): .z
        default: nil
    }
    guard let button else { return nil }
    return ButtonEvent(button: button, pressed: pressed)
}

// MARK: - Mappings

@Observable
class ButtonMappings {
    static let shared = ButtonMappings()

    var map: [KICKRButton: KeyAction] = [
        .up:          .arrowUp,
        .down:        .arrowDown,
        .left:        .arrowLeft,
        .right:       .arrowRight,
        .y:           .tab,
        .b:           .none,
        .a:           .returnKey,
        .z:           .cmdTab,
        .leftInside:  .fnSpace,
        .rightInside: .fn,
    ]

    var shiftMap: [KICKRButton: KeyAction] = [
        .up:    .screenshotArea,
        .down:  .space,
        .left:  .backspace,
        .right: .paste,
    ]

    private let storageKey      = "buttonMappings"
    private let shiftStorageKey = "buttonShiftMappings"

    init() { load() }

    func action(for button: KICKRButton) -> KeyAction { map[button] ?? .none }
    func shiftAction(for button: KICKRButton) -> KeyAction { shiftMap[button] ?? .none }

    func save() {
        let encoded = map.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.rawValue }
        UserDefaults.standard.set(encoded, forKey: storageKey)
        let shiftEncoded = shiftMap.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.rawValue }
        UserDefaults.standard.set(shiftEncoded, forKey: shiftStorageKey)
    }

    func load() {
        if let stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] {
            for button in KICKRButton.allCases {
                if let actionRaw = stored[button.rawValue], let action = KeyAction(rawValue: actionRaw) {
                    map[button] = action
                }
            }
        }
        if let stored = UserDefaults.standard.dictionary(forKey: shiftStorageKey) as? [String: String] {
            for button in KICKRButton.allCases {
                if let actionRaw = stored[button.rawValue], let action = KeyAction(rawValue: actionRaw) {
                    shiftMap[button] = action
                }
            }
        }
    }
}

// MARK: - BLE Manager

let shifterCharUUID = "A026E03C-0A7D-4AB3-97FA-F1500F9FEB8B"

@Observable
class KICKRManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var connected = false
    var deviceName = "Not connected"
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let mappings = ButtonMappings.shared
    private var isShiftHeld = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { central.scanForPeripherals(withServices: nil, options: nil) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? ""
        guard name.lowercased().contains("kickr") || name.lowercased().contains("wahoo") else { return }
        central.stopScan()
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async { self.connected = true; self.deviceName = peripheral.name ?? "KICKR Bike" }
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { self.connected = false; self.deviceName = "Not connected" }
        isShiftHeld = false
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        service.characteristics?.forEach { char in
            guard char.uuid.uuidString.uppercased() == shifterCharUUID else { return }
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid.uuidString.uppercased() == shifterCharUUID,
              let data = characteristic.value,
              let event = parseButtonEvent(data) else { return }
        handleButton(event)
    }

    private func handleButton(_ event: ButtonEvent) {
        if event.button == .b {
            isShiftHeld = event.pressed
            return
        }

        let dpad: [KICKRButton] = [.up, .down, .left, .right]

        if isShiftHeld && dpad.contains(event.button) {
            // Firmware quirk: when B is held, Down emits only a single packet per press
            // with a release-like payload. Up/Left/Right emit both edges normally.
            if event.button == .down {
                fireShiftAction(for: .down)
            } else if event.pressed {
                fireShiftAction(for: event.button)
            }
        } else {
            fireAction(mappings.action(for: event.button), pressed: event.pressed)
        }
    }

    private func fireShiftAction(for button: KICKRButton) {
        let action = mappings.shiftAction(for: button)
        fireAction(action, pressed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            fireAction(action, pressed: false)
        }
    }
}

// MARK: - Settings Window

class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func open() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = NSHostingView(rootView: SettingsView(onPinChanged: { [weak self] pinned in
            self?.setPinned(pinned)
        }))
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "RideControl"
        w.titlebarAppearsTransparent = true
        w.contentView = view
        w.contentMinSize = NSSize(width: 440, height: 320)
        w.contentMaxSize = NSSize(width: 440, height: 10000)
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }

    func setPinned(_ pinned: Bool) {
        window?.level = pinned ? .floating : .normal
    }

    func windowWillClose(_ notification: Notification) {
        window?.level = .normal
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var mappings = ButtonMappings.shared
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var pinOnTop = false
    @AppStorage(screenshotDirKey) private var screenshotSaveDir: String = ""

    let onPinChanged: (Bool) -> Void

    let dpadButtons: [KICKRButton]   = [.up, .down, .left, .right]
    let faceButtons: [KICKRButton]   = [.y, .a, .z]
    let insideButtons: [KICKRButton] = [.leftInside, .rightInside]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 10) {
                    Image("MenuBarIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.primary)
                    VStack(spacing: 2) {
                        Text("RideControl")
                            .font(.system(size: 20, weight: .bold))
                        Text("KICKR Bike Controller")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack {
                    Spacer()
                    Button {
                        pinOnTop.toggle()
                        onPinChanged(pinOnTop)
                    } label: {
                        Image(systemName: pinOnTop ? "pin.fill" : "pin")
                            .rotationEffect(.degrees(pinOnTop ? 0 : 45))
                            .font(.system(size: 14))
                            .foregroundStyle(pinOnTop ? Color.accentColor : Color.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle().fill(pinOnTop ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(pinOnTop ? "Unpin from top" : "Keep window on top")
                    .padding(.trailing, 16)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 12)
            }
            .padding(.top, 16)
            .padding(.bottom, 20)

            Divider()

            Form {
                Section("General") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                            } catch { print("Login item error: \(error)") }
                        }

                    HStack {
                        Text("Screenshot save location")
                        Spacer()
                        Text(screenshotSaveDir.isEmpty
                             ? "Default (system setting)"
                             : (screenshotSaveDir as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            panel.canCreateDirectories = true
                            panel.prompt = "Choose"
                            panel.title = "Choose screenshot save location"
                            if panel.runModal() == .OK, let url = panel.url {
                                screenshotSaveDir = url.path
                            }
                        }
                        if !screenshotSaveDir.isEmpty {
                            Button("Reset") { screenshotSaveDir = "" }
                        }
                    }
                }

                Section("Left (D-Pad)") {
                    ForEach(dpadButtons, id: \.self) { row(for: $0, map: \.map) }
                }

                Section("Left — Shift Layer (hold B)") {
                    ForEach(dpadButtons, id: \.self) { row(for: $0, map: \.shiftMap) }
                }

                Section("Right (Face Buttons)") {
                    ForEach(faceButtons, id: \.self) { row(for: $0, map: \.map) }
                    HStack {
                        Text("B (Bottom)").foregroundStyle(.primary)
                        Spacer()
                        Text("Shift Modifier").foregroundStyle(.secondary).font(.system(size: 13))
                    }
                }

                Section("Inside Levers") {
                    ForEach(insideButtons, id: \.self) { row(for: $0, map: \.map) }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 440)
    }

    @ViewBuilder
    func row(for button: KICKRButton, map keyPath: ReferenceWritableKeyPath<ButtonMappings, [KICKRButton: KeyAction]>) -> some View {
        HStack {
            Picker(button.rawValue, selection: Binding(
                get: { mappings[keyPath: keyPath][button] ?? .none },
                set: { mappings[keyPath: keyPath][button] = $0; mappings.save() }
            )) {
                ForEach(KeyAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }

            if showTestButtons {
                Button {
                    let action = mappings[keyPath: keyPath][button] ?? .none
                    fireAction(action, pressed: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        fireAction(action, pressed: false)
                    }
                } label: {
                    Image(systemName: "play.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - App

@main
struct RideControlApp: App {
    @State private var manager = KICKRManager()

    var body: some Scene {
        MenuBarExtra {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(manager.connected ? Color.green.opacity(0.2) : Color.gray.opacity(0.15))
                        .frame(width: 20, height: 20)
                    Circle()
                        .fill(manager.connected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(manager.connected ? "Connected" : "Searching...")
                        .font(.system(size: 12, weight: .medium))
                    if manager.connected {
                        Text(manager.deviceName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)

            Divider()
            Button("Settings...") { SettingsWindowController.shared.open() }
            Divider()
            Button("Quit RideControl") { NSApplication.shared.terminate(nil) }
        } label: {
            Image("MenuBarIcon")
                .resizable()
                .scaledToFit()
        }
    }
}
