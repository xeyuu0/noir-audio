// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Carbon

@main struct ShortcutTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        var failures = 0, checks = 0
        func check(_ value: Bool, _ name: String) { checks += 1; print("\(value ? "PASS" : "FAIL") \(name)"); if !value { failures += 1 } }
        var preferences = ShortcutPreferences()
        check(!preferences.global, "Global shortcuts require explicit opt-in")
        var duplicate = preferences
        duplicate.actions[StudioAction.mute.rawValue] = duplicate.shortcut(.audio)
        do { try duplicate.validate(); check(false, "Duplicate shortcuts rejected") } catch { check(true, "Duplicate shortcuts rejected") }
        var invalid = preferences
        invalid.actions[StudioAction.record.rawValue]?.key = ""
        do { try invalid.validate(); check(false, "Empty or unsupported keys rejected") } catch { check(true, "Empty or unsupported keys rejected") }
        preferences.global = true
        for action in StudioAction.allCases { preferences.actions[action.rawValue]?.modifiers = .controlOptionCommand }
        var session = Session(); session.shortcuts = preferences
        let data = try JSONEncoder().encode(session), restored = try JSONDecoder().decode(Session.self, from: data)
        check(restored.shortcuts?.global == true && restored.shortcuts?.shortcut(.record) == preferences.shortcut(.record), "Custom shortcuts survive a session round trip")
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "shortcuts")
        let old = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(old.shortcuts == nil, "Sessions written before customizable shortcuts remain loadable")

        let first = GlobalShortcuts(), second = GlobalShortcuts()
        defer { first.shutdown(); second.shutdown() }
        try first.configure(preferences)
        check(true, "macOS registers all five selected global combinations")
        do { try second.configure(preferences); check(false, "OS shortcut conflicts are reported") } catch { check(true, "OS shortcut conflicts are reported") }
        var received: StudioAction?
        first.onAction = { received = $0 }
        var event: EventRef?
        let created = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(kEventAttributeNone), &event)
        guard created == noErr, let event else { throw NoirError.message("Cannot create hotkey test event.") }
        var identifier = EventHotKeyID(signature: 0x4E4F4952, id: 2)
        SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier)
        let sent = SendEventToEventTarget(event, GetApplicationEventTarget())
        ReleaseEvent(event)
        try await Task.sleep(for: .milliseconds(100))
        check(sent == noErr && received == .mute, "Native hotkey event dispatch invokes the matching action on the main actor")
        var local = preferences; local.global = false
        try first.configure(local)
        try second.configure(preferences)
        check(true, "Turning off global shortcuts releases every registered combination")
        second.shutdown()
        try first.configure(preferences)
        check(true, "Shutdown releases registrations for subsequent launches")
        print("RESULT \(checks) shortcut checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
