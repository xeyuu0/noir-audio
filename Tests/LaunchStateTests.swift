// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Combine
import SwiftUI

@main struct LaunchStateTests {
    @MainActor static func main() async throws {
        let testDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/Results")
        let file = testDirectory.appendingPathComponent("launch-test-session.json")
        var session = Session(); session.setupComplete = true
        guard let output = AudioHardware.devices().first(where: { $0.id == AudioHardware.defaultOutput }) else {
            print("FAIL No Core Audio output is available. Run this integration test in a logged-in macOS session with audio-device access.")
            exit(1)
        }
        session.clockUID = output.uid
        try SessionStore.save(session, to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let model = StudioModel(storageURL: file)
        var sceneUpdates = 0, telemetryUpdates = 0, failures = 0
        func check(_ value: Bool, _ text: String) { print("\(value ? "PASS" : "FAIL") \(text)"); if !value { failures += 1 } }
        let sceneSubscription = model.objectWillChange.sink { sceneUpdates += 1 }
        let meterSubscription = model.telemetry.objectWillChange.sink { telemetryUpdates += 1 }
        try await Task.sleep(for: .seconds(1))
        sceneUpdates = 0; telemetryUpdates = 0
        try await Task.sleep(for: .seconds(3))
        check(sceneUpdates == 0, "Idle polling does not invalidate the application scene or command menus")
        check(telemetryUpdates == 0, "Unchanged meters do not publish redundant updates")
        check(model.session.channels[0].deviceUID.isEmpty, "An explicitly disconnected microphone remains disconnected after launch")
        model.startAudio()
        try await Task.sleep(for: .seconds(4))
        check(model.running, "Model starts real HAL output with no microphone permission request")
        sceneUpdates = 0; telemetryUpdates = 0
        try await Task.sleep(for: .seconds(3))
        print("INFO scene updates: \(sceneUpdates); telemetry updates: \(telemetryUpdates)")
        check(sceneUpdates == 0, "Running telemetry is isolated from the application scene")
        check(telemetryUpdates > 10, "Live telemetry continues to update its separate observable object")
        model.showSetup = true
        model.selectedSection = .effects
        check(model.showSetup && model.selectedSection == .effects, "Setup and navigation remain independent of live telemetry")
        model.stopAudio(); model.shutdown()
        withExtendedLifetime([sceneSubscription, meterSubscription]) {}
        print("RESULT \(failures) launch-state regression failures")
        exit(failures == 0 ? 0 : 1)
    }
}
