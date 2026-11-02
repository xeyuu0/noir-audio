// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices

// Exercises the packaged SwiftUI scene, unlike the model-only regression suite.
// Uses existing Accessibility access; never prompts for permission or starts audio.
@main struct LaunchSmoke {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static let appURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("dist/NOIR Audio.app")

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func nodes(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 24 else { return [] }
        let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return [element] + children.flatMap { nodes($0, depth: depth + 1) }
    }
    static func text(_ element: AXUIElement) -> String {
        [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute]
            .compactMap { attribute(element, $0) as? String }.joined(separator: "\n")
    }
    static func wait(_ message: String, seconds: Double = 8, until condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { throw Failure(description: message) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }
    static func window(_ app: AXUIElement) -> AXUIElement? {
        (attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first
    }
    static func button(_ label: String, in app: AXUIElement) -> AXUIElement? {
        guard let window = window(app) else { return nil }
        return nodes(window).first {
            attribute($0, kAXRoleAttribute) as? String == kAXButtonRole && text($0) == label
        }
    }
    static func press(_ label: String, in app: AXUIElement) throws {
        guard let control = button(label, in: app), AXUIElementPerformAction(control, kAXPressAction as CFString) == .success else {
            throw Failure(description: "Cannot press \(label)")
        }
    }
    static func select(_ section: String, caption: String, in app: AXUIElement) throws {
        guard let window = window(app), let row = nodes(window).first(where: {
            attribute($0, kAXRoleAttribute) as? String == kAXRowRole && nodes($0).contains { text($0) == section }
        }), AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success else {
            throw Failure(description: "Cannot select \(section)")
        }
        try wait("\(section) did not render") {
            guard let window = self.window(app) else { return false }
            return nodes(window).contains { text($0) == caption }
        }
    }
    static func launch() throws -> NSRunningApplication {
        var application: NSRunningApplication?, launchError: Error?
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
            application = app; launchError = error
        }
        try wait("Application did not launch") { application != nil || launchError != nil }
        if let launchError { throw launchError }
        return application!
    }
    static func main() {
        do {
            guard AXIsProcessTrusted() else {
                throw Failure(description: "Accessibility access is unavailable. Run this UI test from a terminal with existing Accessibility access, or perform the documented checks manually.")
            }
            let sections = [
                ("Audio Mixer", "Shape the mix. Choose where it goes."),
                ("Virtual Devices", "A direct line between your applications."),
                ("Voice Effects", "Find a voice that feels like yours."),
                ("Soundboard", "A sound for every moment."),
                ("Application Audio", "Bring one application into the mix."),
                ("Recorder", "Keep the take. Catch the moment."),
                ("Broadcasting", "Take your mix on air."),
                ("Settings", "Make this studio your own.")
            ]
            if CommandLine.arguments.contains("--screenshots") {
                let application = try launch()
                let app = AXUIElementCreateApplication(application.processIdentifier)
                try wait("No responsive studio window") { window(app) != nil }
                try wait("Sidebar is still loading") { guard let window = window(app) else { return false }; return nodes(window).contains { text($0) == "Dashboard" } }
                if button("Later", in: app) != nil { try press("Later", in: app) }
                let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Build/WebsiteScreenshots")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let captures = [("Dashboard", "Your sound. Every destination.", "dashboard"), (sections[0].0, sections[0].1, "mixer"), (sections[2].0, sections[2].1, "effects")]
                for (section, caption, name) in captures {
                    try select(section, caption: caption, in: app)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                    guard let id = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == application.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 })?[kCGWindowNumber as String] as? Int else { throw Failure(description: "No visible NOIR window for screenshot") }
                    let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); capture.arguments = ["-x", "-o", "-l", String(id), directory.appendingPathComponent(name + ".png").path]
                    try capture.run(); capture.waitUntilExit()
                    guard capture.terminationStatus == 0 else { throw Failure(description: "NOIR window capture failed") }
                }
                try select("Dashboard", caption: "Your sound. Every destination.", in: app)
                print("Captured three actual NOIR windows in Build/WebsiteScreenshots")
                return
            }
            for cycle in 1...3 {
                let application = try launch()
                let app = AXUIElementCreateApplication(application.processIdentifier)
                AXUIElementSetMessagingTimeout(app, 3)
                try wait("No responsive studio window") { window(app) != nil }
                if button("Later", in: app) != nil { try press("Later", in: app) }
                guard button("Stop audio", in: app) == nil else {
                    throw Failure(description: "Audio is already running; stop it before the restart smoke test.")
                }
                for (section, caption) in sections { try select(section, caption: caption, in: app) }
                print("PASS Launch \(cycle): all nine studio sections respond")
                try press("Run setup assistant", in: app)
                try wait("Setup did not open") { button("Later", in: app) != nil }
                try press("Later", in: app)
                try wait("Setup did not close") { button("Later", in: app) == nil }
                print("PASS Launch \(cycle): setup opens and dismisses without recursion")
                try select("Dashboard", caption: "Your sound. Every destination.", in: app)
                if cycle < 3 {
                    guard application.terminate() else { throw Failure(description: "Normal quit was refused") }
                    try wait("Application did not quit cleanly") { application.isTerminated }
                    print("PASS Launch \(cycle): normal quit completes")
                }
            }
            print("RESULT 0 packaged-app launch failures; app left open on Dashboard, audio stopped")
        } catch { print("FAIL \(error)"); exit(1) }
    }
}
