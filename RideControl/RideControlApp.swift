import SwiftUI
import CoreBluetooth
import CoreGraphics
import AppKit
import ServiceManagement
import UserNotifications

// MARK: - Debug flags

let showTestButtons = false

// MARK: - UserDefaults keys

let screenshotDirKey    = "screenshotSaveDir"
let knownPeripheralKey  = "knownPeripheralID"
let pauseOnSleepKey     = "pauseBluetoothOnSleep"
let profilesKey         = "profiles"
let activeProfileKey    = "activeProfileID"

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
    case cmdReturn      = "Cmd + Return"
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
    case nextProfile    = "Next Profile"
    case prevProfile    = "Previous Profile"
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
    case .cmdReturn where pressed:
        let e = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: true)
        e?.flags = .maskCommand
        e?.post(tap: .cgSessionEventTap)
        let u = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: false)
        u?.flags = .maskCommand
        u?.post(tap: .cgSessionEventTap)
    case .screenshotArea where pressed:
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-ic"]
        task.launch()
    case .screenshotAreaFile where pressed:
        let dir = UserDefaults.standard.string(forKey: screenshotDirKey) ?? ""
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let filename = "Screenshot \(fmt.string(from: Date())).png"
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        if dir.isEmpty {
            // No custom dir chosen — let screencapture use the system default location.
            task.arguments = ["-i"]
            do { try task.run() } catch {
                NSLog("[RideControl] screencapture launch failed: %@", error.localizedDescription)
            }
        } else {
            // Stage to /tmp first (always writable by any process), then move from our
            // own process. The spawned screencapture has a separate TCC token from our
            // app and may be denied direct writes to user folders even when we aren't.
            let tempPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(filename)
            let finalPath = (dir as NSString).appendingPathComponent(filename)
            task.arguments = ["-i", tempPath]
            NSLog("[RideControl] screencapture → temp: %@", tempPath)
            do { try task.run() } catch {
                NSLog("[RideControl] screencapture launch failed: %@", error.localizedDescription)
                break
            }
            DispatchQueue.global(qos: .userInitiated).async {
                task.waitUntilExit()
                NSLog("[RideControl] screencapture exit %d", task.terminationStatus)
                guard task.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: tempPath) else {
                    NSLog("[RideControl] no temp file produced (user cancelled or capture failed)")
                    return
                }
                do {
                    if FileManager.default.fileExists(atPath: finalPath) {
                        try FileManager.default.removeItem(atPath: finalPath)
                    }
                    try FileManager.default.moveItem(atPath: tempPath, toPath: finalPath)
                    NSLog("[RideControl] screenshot saved → %@", finalPath)
                } catch {
                    NSLog("[RideControl] move to %@ failed: %@ — leaving file at %@",
                          finalPath, error.localizedDescription, tempPath)
                }
            }
        }
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
    case .nextProfile where pressed:
        DispatchQueue.main.async { ButtonMappings.shared.cycleProfile(by: 1) }
    case .prevProfile where pressed:
        DispatchQueue.main.async { ButtonMappings.shared.cycleProfile(by: -1) }
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

// MARK: - Profiles

/// A named set of button mappings — one per kind of work (coding, email, Slack…).
/// Stored as `[String: String]` (button raw value → action raw value) so the JSON on
/// disk stays readable and survives adding or renaming buttons and actions.
struct Profile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    private var map: [String: String] = [:]
    private var shiftMap: [String: String] = [:]

    init(name: String,
         map: [KICKRButton: KeyAction] = Profile.defaultMap,
         shiftMap: [KICKRButton: KeyAction] = Profile.defaultShiftMap) {
        self.name = name
        self.map = Profile.encode(map)
        self.shiftMap = Profile.encode(shiftMap)
    }

    func action(for button: KICKRButton, shift: Bool) -> KeyAction {
        let raw = (shift ? shiftMap : map)[button.rawValue]
        return raw.flatMap(KeyAction.init(rawValue:)) ?? .none
    }

    mutating func setAction(_ action: KeyAction, for button: KICKRButton, shift: Bool) {
        if shift { shiftMap[button.rawValue] = action.rawValue }
        else     { map[button.rawValue]      = action.rawValue }
    }

    /// Whether this button has ever been given a binding on that layer. Absence is
    /// meaningful: it distinguishes "never configurable" from a deliberate `.none`,
    /// which is what lets new layer slots be backfilled without stomping a choice.
    func hasBinding(for button: KICKRButton, shift: Bool) -> Bool {
        (shift ? shiftMap : map)[button.rawValue] != nil
    }

    /// A copy under a new name — same bindings, fresh identity.
    func duplicated(named newName: String) -> Profile {
        var copy = self
        copy.id = UUID()
        copy.name = newName
        return copy
    }

    private static func encode(_ dict: [KICKRButton: KeyAction]) -> [String: String] {
        dict.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value.rawValue }
    }

    static let defaultMap: [KICKRButton: KeyAction] = [
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

    static let defaultShiftMap: [KICKRButton: KeyAction] = [
        .up:         .screenshotArea,
        .down:       .space,
        .left:       .backspace,
        .right:      .paste,
        .leftInside: .nextProfile,
    ]

    /// Buttons that can carry a shift-layer action (hold B, then press).
    ///
    /// The right lever is deliberately absent: B and the right lever are both on the
    /// right shifter and can't be pressed together with one hand, so the combination
    /// is unreachable on the actual bike. Don't add it back.
    static let shiftableButtons: [KICKRButton] = [.up, .down, .left, .right, .leftInside]
}

// MARK: - Mappings

@Observable
class ButtonMappings {
    static let shared = ButtonMappings()

    private(set) var profiles: [Profile] = []
    private(set) var activeProfileID: UUID = UUID()

    private let legacyStorageKey      = "buttonMappings"
    private let legacyShiftStorageKey = "buttonShiftMappings"

    init() { load() }

    // MARK: Active profile

    var activeProfile: Profile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    private var activeIndex: Int {
        profiles.firstIndex { $0.id == activeProfileID } ?? 0
    }

    func action(for button: KICKRButton) -> KeyAction {
        activeProfile.action(for: button, shift: false)
    }

    func shiftAction(for button: KICKRButton) -> KeyAction {
        activeProfile.action(for: button, shift: true)
    }

    func setAction(_ action: KeyAction, for button: KICKRButton, shift: Bool) {
        profiles[activeIndex].setAction(action, for: button, shift: shift)
        save()
    }

    // MARK: Switching

    func activate(_ id: UUID, showHUD: Bool = false) {
        guard id != activeProfileID, profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        save()
        if showHUD { announceProfileChange() }
    }

    /// The reference card re-renders itself and already names the profile, so the
    /// toast would only duplicate it — keep the card alive instead.
    private func announceProfileChange() {
        if MappingHUD.shared.isVisible {
            MappingHUD.shared.keepAlive()
        } else {
            ProfileHUD.shared.show(activeProfile.name)
        }
    }

    /// Steps forward (+1) or back (-1) through the profile list, wrapping around.
    /// Used by the "Next / Previous Profile" actions so profiles can be changed
    /// from the handlebars without touching the Mac.
    func cycleProfile(by step: Int) {
        guard profiles.count > 1 else {
            ProfileHUD.shared.show(activeProfile.name, subtitle: "Only profile")
            return
        }
        let next = (activeIndex + step + profiles.count) % profiles.count
        activeProfileID = profiles[next].id
        save()
        announceProfileChange()
    }

    // MARK: Editing

    @discardableResult
    func addProfile(named name: String, copyingActive: Bool) -> UUID {
        let new = copyingActive ? activeProfile.duplicated(named: name) : Profile(name: name)
        profiles.append(new)
        activeProfileID = new.id
        save()
        return new.id
    }

    func renameActive(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profiles[activeIndex].name = trimmed
        save()
    }

    /// Removes the active profile. Refuses to delete the last one — the app
    /// always needs at least one mapping set to fall back on.
    func deleteActive() {
        guard profiles.count > 1 else { return }
        let index = activeIndex
        profiles.remove(at: index)
        activeProfileID = profiles[min(index, profiles.count - 1)].id
        save()
    }

    // MARK: Persistence

    func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        UserDefaults.standard.set(activeProfileID.uuidString, forKey: activeProfileKey)
    }

    func load() {
        var migrated = false
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let stored = try? JSONDecoder().decode([Profile].self, from: data),
           !stored.isEmpty {
            profiles = stored
        } else {
            profiles = migratedProfiles()
            migrated = true
        }

        if let raw = UserDefaults.standard.string(forKey: activeProfileKey),
           let id = UUID(uuidString: raw),
           profiles.contains(where: { $0.id == id }) {
            activeProfileID = id
        } else {
            activeProfileID = profiles[0].id
        }

        // Persist straight away — the freshly built profiles carry new UUIDs, and
        // without writing them the identifiers would differ on every launch.
        if migrated || backfillNewShiftSlots() { save() }
    }

    /// Fills in shift-layer slots that didn't exist when a profile was saved. Only
    /// touches buttons with no binding at all, so a deliberate "None" is left alone.
    private func backfillNewShiftSlots() -> Bool {
        var changed = false
        for index in profiles.indices {
            for (button, action) in Profile.defaultShiftMap
            where !profiles[index].hasBinding(for: button, shift: true) {
                profiles[index].setAction(action, for: button, shift: true)
                changed = true
            }
        }
        return changed
    }

    /// First run under the profile system: carry the user's existing single mapping
    /// forward untouched as "Vibe Coding", then seed two more copies to customise.
    private func migratedProfiles() -> [Profile] {
        var map = Profile.defaultMap
        var shiftMap = Profile.defaultShiftMap

        if let stored = UserDefaults.standard.dictionary(forKey: legacyStorageKey) as? [String: String] {
            for button in KICKRButton.allCases {
                if let raw = stored[button.rawValue], let action = KeyAction(rawValue: raw) {
                    map[button] = action
                }
            }
        }
        if let stored = UserDefaults.standard.dictionary(forKey: legacyShiftStorageKey) as? [String: String] {
            for button in KICKRButton.allCases {
                if let raw = stored[button.rawValue], let action = KeyAction(rawValue: raw) {
                    shiftMap[button] = action
                }
            }
        }

        let base = Profile(name: "Vibe Coding", map: map, shiftMap: shiftMap)
        return [base, base.duplicated(named: "Email"), base.duplicated(named: "Slack")]
    }
}

// MARK: - HUD

/// The system HUD material. `NSVisualEffectView.Material.hudWindow` is the same
/// backing macOS uses for its own heads-up panels.
private struct HUDBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Builds the shared non-activating panel both HUDs use. Never becomes key, so it
/// can't steal focus from whatever you're actually working in.
private func makeHUDPanel() -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 220, height: 110),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .statusBar
    panel.ignoresMouseEvents = true
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    // The HUD material is dark in both themes, so pin the appearance — otherwise in
    // Light Mode the labels resolve to near-black and vanish into the background.
    panel.appearance = NSAppearance(named: .darkAqua)
    return panel
}

// MARK: - Mapping cheat sheet HUD

private struct MappingHUDView: View {
    // Reads the store rather than taking a snapshot, so switching profiles while the
    // card is open re-renders it in place instead of leaving stale bindings on screen.
    private let mappings = ButtonMappings.shared
    private var profile: Profile { mappings.activeProfile }

    private let dpad: [KICKRButton]   = [.up, .down, .left, .right]
    private let face: [KICKRButton]   = [.y, .a, .z]
    private let levers: [KICKRButton] = [.leftInside, .rightInside]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 13))
                Text(profile.name).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("double-press B to close")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    column("Left — D-Pad", dpad, shift: false)
                    column("Right — Face", face, shift: false)
                }
                VStack(alignment: .leading, spacing: 14) {
                    column("Hold B +", Profile.shiftableButtons, shift: true)
                    column("Inside Levers", levers, shift: false)
                }
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(HUDBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func column(_ title: String, _ buttons: [KICKRButton], shift: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            ForEach(buttons, id: \.self) { button in
                HStack(spacing: 8) {
                    Text(button.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 88, alignment: .leading)
                    Text(profile.action(for: button, shift: shift).rawValue)
                        .font(.system(size: 12))
                        .foregroundStyle(
                            profile.action(for: button, shift: shift) == .none ? .tertiary : .secondary
                        )
                        .lineLimit(1)
                }
            }
        }
    }
}

/// The button reference card. Toggled by double-pressing B, and self-dismissing so
/// it can never get stuck on screen while you're riding.
final class MappingHUD {
    static let shared = MappingHUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private(set) var isVisible = false

    private let autoHideAfter: TimeInterval = 20

    func toggle() {
        if Thread.isMainThread { isVisible ? hide() : show() }
        else { DispatchQueue.main.async { self.isVisible ? self.hide() : self.show() } }
    }

    func show() {
        let panel = self.panel ?? makeHUDPanel()
        self.panel = panel

        let host = NSHostingView(rootView: MappingHUDView())
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.midY - panel.frame.height / 2
            ))
        }

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        isVisible = true
        armAutoHide()
    }

    /// Restarts the dismiss countdown. Cycling profiles with the card open is active
    /// use, so it shouldn't disappear part-way through.
    func keepAlive() {
        guard isVisible else { return }
        armAutoHide()
    }

    private func armAutoHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideAfter, execute: work)
    }

    func hide() {
        hideWork?.cancel(); hideWork = nil
        isVisible = false
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }
}

// MARK: - Profile HUD

private struct HUDView: View {
    let text: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1)
            Text(subtitle ?? "Profile")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(minWidth: 200)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 20, y: 6)
    }
}

/// Transient, non-focus-stealing overlay confirming a profile switch. The rider
/// is on the bike and can't check the menu bar, so the feedback comes to them.
final class ProfileHUD {
    static let shared = ProfileHUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ name: String, subtitle: String? = nil) {
        if Thread.isMainThread { present(name, subtitle) }
        else { DispatchQueue.main.async { self.present(name, subtitle) } }
    }

    private func present(_ name: String, _ subtitle: String?) {
        hideWork?.cancel()

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let host = NSHostingView(rootView: HUDView(text: name, subtitle: subtitle))
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.minY + visible.height * 0.14
            ))
        }

        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            guard let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    private func makePanel() -> NSPanel { makeHUDPanel() }
}

// MARK: - Logging

/// Appends to ~/Library/Logs/RideControl.log. NSLog alone is not enough here:
/// nothing this app writes shows up in the unified log via `log show`, which makes
/// connection problems impossible to diagnose after the fact.
func rcLog(_ message: String) {
    NSLog("[RideControl] %@", message)

    let stamp = ISO8601DateFormatter().string(from: Date())
    guard let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Logs") else { return }
    let url = dir.appendingPathComponent("RideControl.log")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let line = Data("\(stamp)  \(message)\n".utf8)
    if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    } else {
        try? line.write(to: url)
    }
}

// MARK: - BLE Manager

let shifterCharUUID = "A026E03C-0A7D-4AB3-97FA-F1500F9FEB8B"

@Observable
class KICKRManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var connected = false
    var deviceName = "Not connected"
    var status = "Starting…"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let mappings = ButtonMappings.shared
    private var isShiftHeld = false

    // Double-press on B opens the mapping cheat sheet. Tracked here so that a
    // press only counts when the previous hold didn't actually use the shift
    // layer — otherwise two quick shifted actions would trip it by accident.
    private var lastBPressAt: TimeInterval = 0
    private var shiftUsedThisHold = false
    private let doublePressWindow: TimeInterval = 0.5

    // Scan lifecycle. Scanning is the expensive part: an open scan makes the
    // Bluetooth controller wake the host to deliver every advertisement in
    // range, which shows up as a dark wake every ~45s overnight. So we scan
    // only when we have never seen the bike, in short windows with backoff,
    // and rely on a pending connection (handled inside the controller) after that.
    private var scanStopWork: DispatchWorkItem?
    private var scanRetryWork: DispatchWorkItem?
    private var scanBackoff: TimeInterval = 20
    private let scanWindow: TimeInterval = 12
    private let maxBackoff: TimeInterval = 120

    // Retrying a failed connect must always go through a timer. CoreBluetooth can
    // invoke didFailToConnect synchronously from inside connect(), so reconnecting
    // straight from the delegate recurses until the stack overflows.
    private var reconnectWork: DispatchWorkItem?
    private var reconnectDelay: TimeInterval = 2
    private let maxReconnectDelay: TimeInterval = 60

    // A stored identifier can go stale — CoreBluetooth still hands back a peripheral
    // object for it, but connecting fails immediately. Without a way back to
    // scanning the app would sit on "Waiting for bike" forever, so every pending
    // connect is watched and falls back to a scan if it doesn't land.
    private var connectWatchdog: DispatchWorkItem?
    private let connectTimeout: TimeInterval = 15
    private var failedScanRounds = 0
    private let scanRoundsBeforeIdle = 3

    private var isSuspended = false

    private var pausesOnSleep: Bool {
        UserDefaults.standard.object(forKey: pauseOnSleepKey) as? Bool ?? true
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemWillSleep),
                           name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(systemDidWake),
                           name: NSWorkspace.didWakeNotification, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Sleep / wake

    /// Tear the radio work down before the Mac sleeps. Without this, a pending
    /// connection or open scan keeps bluetoothd's PreventUserIdleSystemSleep
    /// assertion alive and the machine bounces in and out of standby all night.
    @objc private func systemWillSleep() {
        guard pausesOnSleep else { return }
        isSuspended = true
        cancelScanTimers()
        reconnectWork?.cancel(); reconnectWork = nil
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        NSLog("[RideControl] system sleeping — Bluetooth released")
        setStatus(connected: false, name: "Not connected", status: "Paused — Mac asleep")
    }

    @objc private func systemDidWake() {
        guard isSuspended else { return }
        isSuspended = false
        scanBackoff = 20
        NSLog("[RideControl] system woke — resuming Bluetooth")
        beginConnecting()
    }

    // MARK: - Connection strategy

    private func beginConnecting() {
        guard !isSuspended, central?.state == .poweredOn else { return }

        // Reconnect to the bike we already know without scanning, but keep the
        // watchdog armed so a stale identifier can't strand us.
        if let known = knownPeripheral() {
            connectPending(known, watchdog: true)
            return
        }
        startScanWindow()
    }

    private func knownPeripheral() -> CBPeripheral? {
        guard let raw = UserDefaults.standard.string(forKey: knownPeripheralKey),
              let uuid = UUID(uuidString: raw) else { return nil }
        return central.retrievePeripherals(withIdentifiers: [uuid]).first
    }

    /// Ask CoreBluetooth to connect whenever the bike shows up. This request is
    /// serviced by the Bluetooth controller itself — unlike a scan, it does not
    /// wake the host for unrelated advertisements, so it costs effectively nothing
    /// while the bike is switched off.
    ///
    /// `watchdog` falls back to scanning if the connection doesn't land in time.
    /// It's off only once we've settled — bike presumed switched off — where an
    /// indefinite pending connect is exactly what we want.
    private func connectPending(_ peripheral: CBPeripheral, watchdog: Bool) {
        cancelScanTimers()
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        // No options: CBConnectPeripheralOptionEnableAutoReconnect is rejected on
        // macOS ("One or more parameters were invalid") and makes every connect fail
        // instantly. A plain connect already pends indefinitely, which is what we
        // want — didDisconnect re-arms it for the auto-reconnect behaviour.
        central.connect(peripheral, options: nil)
        rcLog("pending connect armed for \(peripheral.identifier.uuidString) (watchdog: \(watchdog))")
        setStatus(connected: false, name: "Not connected", status: "Waiting for bike")

        connectWatchdog?.cancel()
        guard watchdog else { connectWatchdog = nil; return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isSuspended, !self.connected else { return }
            rcLog("pending connect did not land in \(Int(self.connectTimeout))s — falling back to scan")
            self.startScanWindow()
        }
        connectWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + connectTimeout, execute: work)
    }

    private func startScanWindow() {
        guard !isSuspended, central.state == .poweredOn else { return }
        cancelScanTimers()
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        NSLog("[RideControl] scan started (%.0fs window)", scanWindow)
        setStatus(connected: false, name: "Not connected", status: "Searching…")

        let stop = DispatchWorkItem { [weak self] in
            guard let self, !self.isSuspended else { return }
            self.central.stopScan()
            self.failedScanRounds += 1

            // Bike looks switched off. Stop burning the radio on repeated scans and
            // settle into a pending connect, which costs nothing until it shows up.
            if self.failedScanRounds >= self.scanRoundsBeforeIdle, let known = self.knownPeripheral() {
                rcLog("bike not found after \(self.failedScanRounds) scans — idling on pending connect")
                self.connectPending(known, watchdog: false)
                return
            }

            rcLog("scan found nothing — retrying in \(Int(self.scanBackoff))s")
            self.setStatus(connected: false, name: "Not connected", status: "Bike not found")

            let retry = DispatchWorkItem { [weak self] in self?.startScanWindow() }
            self.scanRetryWork = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + self.scanBackoff, execute: retry)
            self.scanBackoff = min(self.scanBackoff * 2, self.maxBackoff)
        }
        scanStopWork = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + scanWindow, execute: stop)
    }

    private func cancelScanTimers() {
        scanStopWork?.cancel();  scanStopWork = nil
        scanRetryWork?.cancel(); scanRetryWork = nil
        connectWatchdog?.cancel(); connectWatchdog = nil
    }

    /// Re-arms the pending connection off the current call stack, with backoff.
    private func scheduleReconnect(_ peripheral: CBPeripheral) {
        reconnectWork?.cancel()
        let delay = reconnectDelay
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isSuspended else { return }
            self.connectPending(peripheral, watchdog: true)
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
    }

    private func setStatus(connected: Bool, name: String, status: String) {
        DispatchQueue.main.async {
            self.connected = connected
            self.deviceName = name
            self.status = status
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginConnecting()
        case .poweredOff:
            cancelScanTimers()
            setStatus(connected: false, name: "Not connected", status: "Bluetooth off")
        case .unauthorized:
            cancelScanTimers()
            setStatus(connected: false, name: "Not connected", status: "Bluetooth not permitted")
        default:
            cancelScanTimers()
            setStatus(connected: false, name: "Not connected", status: "Bluetooth unavailable")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (peripheral.name ?? "").lowercased()
        guard name.contains("kickr") || name.contains("wahoo") else { return }
        rcLog("discovered \(peripheral.name ?? "?") \(peripheral.identifier.uuidString)")
        scanBackoff = 20
        failedScanRounds = 0
        // Deliberately not saved yet — an identifier is only worth remembering once
        // it has actually produced a connection.
        connectPending(peripheral, watchdog: true)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        cancelScanTimers()
        reconnectWork?.cancel(); reconnectWork = nil
        central.stopScan()
        scanBackoff = 20
        reconnectDelay = 2
        failedScanRounds = 0
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: knownPeripheralKey)
        rcLog("connected to \(peripheral.name ?? "KICKR Bike")")
        setStatus(connected: true, name: peripheral.name ?? "KICKR Bike", status: "Connected")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isShiftHeld = false
        guard !isSuspended else { return }
        cancelScanTimers()
        rcLog("connect failed: \(error?.localizedDescription ?? "no error")")

        // The identifier we were handed doesn't actually connect. Forget it and
        // rediscover from scratch rather than retrying it forever.
        let stored = UserDefaults.standard.string(forKey: knownPeripheralKey)
        if stored == peripheral.identifier.uuidString {
            rcLog("discarding stale stored identifier \(peripheral.identifier.uuidString)")
            UserDefaults.standard.removeObject(forKey: knownPeripheralKey)
        }
        setStatus(connected: false, name: "Not connected", status: "Searching…")
        // Off the current stack: CoreBluetooth can call this synchronously from connect().
        DispatchQueue.main.async { [weak self] in self?.startScanWindow() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isShiftHeld = false
        guard !isSuspended else { return }
        // Re-arm the pending connection rather than falling back to a scan —
        // we already know which device we want.
        setStatus(connected: false, name: "Not connected", status: "Waiting for bike")
        scheduleReconnect(peripheral)
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
            if event.pressed {
                let now = Date().timeIntervalSinceReferenceDate
                // Two presses in quick succession, neither of which was used to
                // shift anything: that's the cheat-sheet gesture.
                if now - lastBPressAt < doublePressWindow && !shiftUsedThisHold {
                    MappingHUD.shared.toggle()
                }
                lastBPressAt = now
                shiftUsedThisHold = false
            }
            isShiftHeld = event.pressed
            return
        }

        if isShiftHeld && Profile.shiftableButtons.contains(event.button) {
            shiftUsedThisHold = true
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
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "RideControl"
        w.titlebarAppearsTransparent = true
        w.contentView = view
        w.contentMinSize = NSSize(width: 360, height: 320)
        w.contentMaxSize = NSSize(width: 1200, height: 10000)
        let autosaveName = "RideControlSettingsWindow"
        let restored = w.setFrameUsingName(autosaveName)
        w.setFrameAutosaveName(autosaveName)
        if !restored { w.center() }
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
    @State private var nameDraft = ""
    @AppStorage(screenshotDirKey) private var screenshotSaveDir: String = ""
    @AppStorage(pauseOnSleepKey) private var pauseOnSleep: Bool = true

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return short
    }

    let onPinChanged: (Bool) -> Void

    let dpadButtons: [KICKRButton]   = [.up, .down, .left, .right]
    let faceButtons: [KICKRButton]   = [.y, .a, .z]
    let insideButtons: [KICKRButton] = [.leftInside, .rightInside]

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image("MenuBarIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.primary)
                    VStack(spacing: 1) {
                        Text("RideControl")
                            .font(.system(size: 17, weight: .bold))
                        Text("KICKR Bike Controller · v\(appVersion)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                Button {
                    pinOnTop.toggle()
                    onPinChanged(pinOnTop)
                } label: {
                    Image(systemName: pinOnTop ? "pin.fill" : "pin")
                        .rotationEffect(.degrees(pinOnTop ? 0 : 45))
                        .font(.system(size: 13))
                        .foregroundStyle(pinOnTop ? Color.accentColor : Color.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle().fill(pinOnTop ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(pinOnTop ? "Unpin from top" : "Keep window on top")
                .padding(.top, 8)
                .padding(.trailing, 12)
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            Form {
                Section("Profile") {
                    Picker("Active profile", selection: Binding(
                        get: { mappings.activeProfileID },
                        set: { mappings.activate($0) }
                    )) {
                        ForEach(mappings.profiles) { Text($0.name).tag($0.id) }
                    }

                    HStack {
                        // Edited through a local draft so the field can be cleared and
                        // retyped — committing straight to the model would refuse the
                        // empty string and snap the old name back mid-edit.
                        TextField("Name", text: $nameDraft)
                            .textFieldStyle(.roundedBorder)
                            .onAppear { nameDraft = mappings.activeProfile.name }
                            .onChange(of: mappings.activeProfileID) { _, _ in
                                nameDraft = mappings.activeProfile.name
                            }
                            .onChange(of: nameDraft) { _, new in
                                mappings.renameActive(to: new)
                            }

                        Button("Duplicate") {
                            mappings.addProfile(named: "\(mappings.activeProfile.name) copy",
                                                copyingActive: true)
                        }
                        Button("New") {
                            mappings.addProfile(named: "New Profile", copyingActive: false)
                        }
                        Button("Delete", role: .destructive) { confirmDeleteProfile() }
                            .disabled(mappings.profiles.count < 2)
                    }

                    Text("Bind a button to “Next Profile” to switch between these from the handlebars.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section("General") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                            } catch { print("Login item error: \(error)") }
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Disconnect while the Mac is asleep", isOn: $pauseOnSleep)
                        Text("Stops the bike connection at sleep and restores it on wake, so RideControl can’t wake the Mac overnight. Reconnects a second or two after you open the lid.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
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
                                // Verify we can actually write to the chosen folder.
                                // On modern macOS, attempting a real write here will surface
                                // any TCC permission prompt up front rather than silently
                                // failing later when a screenshot fires.
                                let testURL = url.appendingPathComponent(".ridecontrol-write-test")
                                do {
                                    try Data().write(to: testURL)
                                    try? FileManager.default.removeItem(at: testURL)
                                    screenshotSaveDir = url.path
                                } catch {
                                    let alert = NSAlert()
                                    alert.messageText = "RideControl can't write to that folder"
                                    alert.informativeText = """
                                        Couldn't save a test file to "\(url.path)".

                                        \(error.localizedDescription)

                                        Open System Settings → Privacy & Security → Files and Folders, find RideControl, and toggle on access for the folder you want to use. Then try Choose… again.

                                        If RideControl isn't listed, try a different folder (e.g. ~/Pictures), or build a release version installed to /Applications — debug builds run from Xcode get a new identity each rebuild and may be denied silently.
                                        """
                                    alert.alertStyle = .warning
                                    alert.addButton(withTitle: "Open System Settings")
                                    alert.addButton(withTitle: "Cancel")
                                    let response = alert.runModal()
                                    if response == .alertFirstButtonReturn,
                                       let prefsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                                        NSWorkspace.shared.open(prefsURL)
                                    }
                                }
                            }
                        }
                        if !screenshotSaveDir.isEmpty {
                            Button("Reset") { screenshotSaveDir = "" }
                        }
                    }
                }

                Section("Left (D-Pad)") {
                    ForEach(dpadButtons, id: \.self) { row(for: $0, shift: false) }
                }

                Section("Shift Layer (hold B)") {
                    ForEach(Profile.shiftableButtons, id: \.self) { row(for: $0, shift: true) }
                }

                Section("Right (Face Buttons)") {
                    ForEach(faceButtons, id: \.self) { row(for: $0, shift: false) }
                    HStack {
                        Text("B (Bottom)").foregroundStyle(.primary)
                        Spacer()
                        Text("Shift Modifier").foregroundStyle(.secondary).font(.system(size: 13))
                    }
                }

                Section("Inside Levers") {
                    ForEach(insideButtons, id: \.self) { row(for: $0, shift: false) }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 360)
    }

    private func confirmDeleteProfile() {
        let alert = NSAlert()
        alert.messageText = "Delete “\(mappings.activeProfile.name)”?"
        alert.informativeText = "Its button mappings will be removed. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { mappings.deleteActive() }
    }

    @ViewBuilder
    func row(for button: KICKRButton, shift: Bool) -> some View {
        HStack {
            Picker(button.rawValue, selection: Binding(
                get: { mappings.activeProfile.action(for: button, shift: shift) },
                set: { mappings.setAction($0, for: button, shift: shift) }
            )) {
                ForEach(KeyAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }

            if showTestButtons {
                Button {
                    let action = mappings.activeProfile.action(for: button, shift: shift)
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
    @State private var mappings = ButtonMappings.shared

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
                    Text(manager.status)
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
            Section("Profile") {
                ForEach(mappings.profiles) { profile in
                    Button {
                        mappings.activate(profile.id, showHUD: true)
                    } label: {
                        if profile.id == mappings.activeProfileID {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            }

            Divider()
            Button("Button Reference") { MappingHUD.shared.show() }
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
