// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

enum DriverManager {
    static var installer: URL? { Bundle.main.url(forResource: "NOIR Audio Drivers", withExtension: "pkg") }
    static func install() throws {
        guard let url = installer else { throw NoirError.message("Driver installer is not bundled in this development build. Run Scripts/build-drivers.sh, rebuild the app, or open dist/NOIR Audio Drivers.pkg.") }
        guard NSWorkspace.shared.open(url) else { throw NoirError.message("macOS Installer could not open the driver package.") }
    }
    static func remove() throws {
        guard let script = Bundle.main.url(forResource: "uninstall-drivers", withExtension: "sh") else { throw NoirError.message("The driver removal script is missing.") }
        let quoted = "'" + script.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = "/bin/sh " + quoted
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(literal)\" with administrator privileges")?.executeAndReturnError(&error)
        if let error { throw NoirError.message("Driver removal did not complete: \(error[NSAppleScript.errorMessage] ?? "administrator authorization was cancelled").") }
    }
}
