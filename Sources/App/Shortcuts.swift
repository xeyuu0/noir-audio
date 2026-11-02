// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Carbon

enum StudioAction: String, Codable, CaseIterable, Identifiable {
    case audio, mute, deafen, record, replay
    var id: String { rawValue }
    var label: String { switch self { case .audio: "Start / stop audio"; case .mute: "Mute microphone"; case .deafen: "Deafen Monitor"; case .record: "Start / stop recording"; case .replay: "Save replay" } }
    var defaultKey: String { switch self { case .audio: "a"; case .mute: "m"; case .deafen: "d"; case .record: "r"; case .replay: "s" } }
}
enum ShortcutModifiers: String, Codable, CaseIterable, Identifiable {
    case commandShift, commandOption, controlOptionCommand
    var id: String { rawValue }
    var label: String { switch self { case .commandShift: "⇧⌘"; case .commandOption: "⌥⌘"; case .controlOptionCommand: "⌃⌥⌘" } }
    var swiftUI: SwiftUI.EventModifiers { switch self { case .commandShift: [.command, .shift]; case .commandOption: [.command, .option]; case .controlOptionCommand: [.control, .option, .command] } }
    var carbon: UInt32 { switch self { case .commandShift: UInt32(cmdKey | shiftKey); case .commandOption: UInt32(cmdKey | optionKey); case .controlOptionCommand: UInt32(controlKey | optionKey | cmdKey) } }
}
struct StudioShortcut: Codable, Equatable {
    var key: String
    var modifiers: ShortcutModifiers = .commandShift
    static let keyCodes: [String: UInt32] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46]
    var description: String { modifiers.label + key.uppercased() }
}
struct ShortcutPreferences: Codable {
    var global = false
    var actions = Dictionary(uniqueKeysWithValues: StudioAction.allCases.map { ($0.rawValue, StudioShortcut(key: $0.defaultKey)) })
    func shortcut(_ action: StudioAction) -> StudioShortcut { actions[action.rawValue] ?? StudioShortcut(key: action.defaultKey) }
    func validate() throws {
        let choices = StudioAction.allCases.map(shortcut)
        guard choices.allSatisfy({ StudioShortcut.keyCodes[$0.key] != nil }), Set(choices.map(\.description)).count == choices.count else { throw NoirError.message("Choose a different letter or number for each shortcut combination.") }
    }
}

@MainActor final class GlobalShortcuts {
    var onAction: ((StudioAction) -> Void)?
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private func installHandler() throws {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == 0x4E4F4952, identifier.id > 0, identifier.id <= StudioAction.allCases.count else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            let action = StudioAction.allCases[Int(identifier.id)-1]
            Task { @MainActor in owner.onAction?(action) }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw NoirError.message("Global shortcut handling is unavailable (\(status)). Local shortcuts remain available.") }
    }
    func configure(_ preferences: ShortcutPreferences) throws {
        clear(); try preferences.validate()
        guard preferences.global else { return }
        try installHandler()
        for (index, action) in StudioAction.allCases.enumerated() {
            let shortcut = preferences.shortcut(action)
            var registration: EventHotKeyRef?
            let status = RegisterEventHotKey(StudioShortcut.keyCodes[shortcut.key]!, shortcut.modifiers.carbon,
                                            EventHotKeyID(signature: 0x4E4F4952, id: UInt32(index+1)), GetApplicationEventTarget(), 0, &registration)
            guard status == noErr, let registration else { clear(); throw NoirError.message("\(shortcut.description) could not be registered globally (\(status)). Choose another shortcut; local shortcuts remain available.") }
            registrations.append(registration)
        }
    }
    func clear() {
        for item in registrations { UnregisterEventHotKey(item) }; registrations.removeAll()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
    func shutdown() { clear(); onAction = nil }
}
struct StudioShortcutModifier: ViewModifier {
    let shortcut: StudioShortcut
    let local: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if local { content.keyboardShortcut(KeyEquivalent(Character(shortcut.key)), modifiers: shortcut.modifiers.swiftUI) }
        else { content }
    }
}
