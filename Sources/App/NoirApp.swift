// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = StudioModel()
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
@main struct NoirAudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("showMenuBar") private var showMenuBar = true
    private var model: StudioModel { delegate.model }
    var body: some Scene {
        WindowGroup("NOIR Audio") {
            StudioView().environmentObject(model).environmentObject(model.telemetry).preferredColorScheme(.dark)
                .onAppear { model.presentFirstSetup() }
                .frame(minWidth: 1040, minHeight: 720)
        }
        .defaultSize(width: 1300, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands { StudioCommands(model: model) }
        MenuBarExtra("NOIR Audio", systemImage: "waveform", isInserted: $showMenuBar) {
            StudioMenu(model: model)
        }
    }
}
struct StudioCommands: Commands {
    @ObservedObject var model: StudioModel
    var body: some Commands {
            CommandGroup(after: .newItem) {
                Button("Open Mixer Preset…", action: model.loadPreset).keyboardShortcut("o")
                Button("Save Mixer Preset…", action: model.savePreset).keyboardShortcut("s")
            }
            CommandMenu("Audio") {
                Button(model.running ? "Stop Audio" : "Start Audio") { model.perform(.audio) }.modifier(StudioShortcutModifier(shortcut: model.shortcut(.audio), local: !model.globalShortcutsActive))
                Button("Mute Microphone") { model.perform(.mute) }.modifier(StudioShortcutModifier(shortcut: model.shortcut(.mute), local: !model.globalShortcutsActive))
                Button("Deafen Monitor") { model.perform(.deafen) }.modifier(StudioShortcutModifier(shortcut: model.shortcut(.deafen), local: !model.globalShortcutsActive))
                Button(model.recording ? "Stop Recording" : "Start Recording") { model.perform(.record) }.modifier(StudioShortcutModifier(shortcut: model.shortcut(.record), local: !model.globalShortcutsActive))
                Button("Save Instant Replay") { model.perform(.replay) }.modifier(StudioShortcutModifier(shortcut: model.shortcut(.replay), local: !model.globalShortcutsActive))
                Button("Stop All Clips", action: model.stopAllClips).keyboardShortcut(.escape, modifiers: [])
            }
    }
}
struct StudioMenu: View {
    @ObservedObject var model: StudioModel
    var body: some View {
            Text(model.running ? "Audio running" : "Audio stopped")
            Button(model.running ? "Stop Audio" : "Start Audio", action: model.toggleAudio)
            Button("Mute Microphone") { model.session.channels[0].mute.toggle(); model.syncControls() }
            Button("Deafen Monitor") { model.session.buses[1].mute.toggle(); model.syncControls() }
            Button("Save Replay", action: model.saveReplay)
            Divider()
            Button("Quit NOIR Audio") { NSApp.terminate(nil) }
    }
}
