// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

enum StudioSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard", mixer = "Audio Mixer", virtual = "Virtual Devices", effects = "Voice Effects", soundboard = "Soundboard", capture = "Application Audio", recorder = "Recorder", broadcast = "Broadcasting", settings = "Settings"
    var id: String { rawValue }
    var symbol: String { switch self { case .dashboard: "square.grid.2x2"; case .mixer: "slider.vertical.3"; case .virtual: "point.3.connected.trianglepath.dotted"; case .effects: "waveform.path"; case .soundboard: "square.grid.3x3"; case .capture: "macwindow.on.rectangle"; case .recorder: "record.circle"; case .broadcast: "antenna.radiowaves.left.and.right"; case .settings: "gearshape" } }
    var caption: String { switch self { case .dashboard: "Your sound. Every destination."; case .mixer: "Shape the mix. Choose where it goes."; case .virtual: "A direct line between your applications."; case .effects: "Find a voice that feels like yours."; case .soundboard: "A sound for every moment."; case .capture: "Bring one application into the mix."; case .recorder: "Keep the take. Catch the moment."; case .broadcast: "Take your mix on air."; case .settings: "Make this studio your own." } }
}
struct StudioView: View {
    @EnvironmentObject private var model: StudioModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform").font(.system(size: 25, weight: .light)).frame(width: 44, height: 44).modifier(GlassSurface())
                    VStack(alignment: .leading, spacing: 2) { Text("NOIR").font(.system(size: 23, weight: .semibold)).tracking(5); Text("A U D I O   S T U D I O").font(.system(size: 7, weight: .medium)).foregroundStyle(Noir.secondary) }
                }.padding(.horizontal, 22).padding(.top, 34)
                List(selection: $model.selectedSection) {
                    Section("STUDIO") { ForEach(Array(StudioSection.allCases.prefix(6))) { section in sidebarRow(section) } }
                    Section("OUTPUT") { sidebarRow(.recorder); sidebarRow(.broadcast) }
                    Section { sidebarRow(.settings) }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                SidebarEngineStatus().padding(16)
            }.modifier(GlassSurface(radius: 24)).padding(10).navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 250)
        } detail: {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 9) { Text(model.selectedSection.rawValue).font(.system(size: 32, weight: .medium)); Text(model.selectedSection.caption).font(.system(size: 13)).foregroundStyle(Noir.secondary) }
                            Spacer()
                            if model.selectedSection == .dashboard { Tag(text: "STUDIO  /  01") }
                        }.padding(.bottom, 7)
                        section
                            .id(model.selectedSection)
                            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 7)))
                    }.padding(30).frame(maxWidth: 1500, alignment: .leading)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: model.selectedSection)
                }
                HStack(spacing: 12) { Image(systemName: "info.circle"); Text(model.notice).lineLimit(2); Spacer(); Text("NOIR  0.1").font(.system(size: 9, design: .monospaced)) }.font(.system(size: 11)).foregroundStyle(Noir.secondary).padding(.horizontal, 30).padding(.vertical, 12).modifier(GlassSurface(radius: 14)).padding(.horizontal, 16).padding(.bottom, 12)
            }.background(.clear)
        }
        .background { NoirBackdrop() }
        .tint(.white).foregroundStyle(.white).saturation(0)
        .sheet(isPresented: $model.showSetup) { SetupView().environmentObject(model) }
        .alert("Studio needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private func sidebarRow(_ section: StudioSection) -> some View { Label(section.rawValue, systemImage: section.symbol).font(.system(size: 12, weight: model.selectedSection == section ? .semibold : .regular)).padding(.vertical, 6).tag(section) }
    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) { Image(systemName: "circle.dotted"); Text(model.session.name) }.font(.system(size: 12)).foregroundStyle(Noir.secondary)
            Spacer()
            if model.recording { Label("RECORDING", systemImage: "record.circle.fill").font(.system(size: 10, weight: .semibold, design: .monospaced)) }
            Button { model.perform(.mute) } label: { Image(systemName: model.session.channels[0].mute ? "mic.slash" : "mic") }.help("Mute microphone · \(model.shortcut(.mute).description)").accessibilityLabel("Mute microphone")
            Button { model.perform(.deafen) } label: { Image(systemName: model.session.buses[1].mute ? "speaker.slash" : "headphones") }.help("Deafen monitor · \(model.shortcut(.deafen).description)").accessibilityLabel("Deafen monitor")
            Divider().frame(height: 18)
            Button(action: model.toggleAudio) { Label(model.busy ? "Starting…" : model.running ? "Stop audio" : "Start audio", systemImage: model.running ? "stop.fill" : "play.fill").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 5) }.disabled(model.busy).buttonStyle(PrimaryButtonStyle())
        }.buttonStyle(.borderless).padding(.horizontal, 30).frame(height: 66).modifier(GlassSurface(radius: 20)).padding(.horizontal, 16).padding(.top, 10)
    }
    @ViewBuilder private var section: some View {
        switch model.selectedSection {
        case .dashboard: DashboardView()
        case .mixer: MixerView()
        case .effects: EffectsView()
        case .soundboard: SoundboardView()
        case .capture: CaptureView()
        case .recorder: RecorderView()
        case .virtual: DriverView()
        case .settings: SettingsView()
        case .broadcast: BroadcastView()
        }
    }
}
private struct SidebarEngineStatus: View {
    @EnvironmentObject var model: StudioModel
    @EnvironmentObject var telemetry: EngineTelemetry
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Circle().fill(.white.opacity(model.running ? 1 : 0.25)).frame(width: 6, height: 6); Text(model.running ? "ENGINE RUNNING" : "ENGINE OFFLINE").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1) }
            MeterView(peak: telemetry.snapshot.peaks[6], rms: telemetry.snapshot.rms[6])
            Text("48 kHz  ·  \(model.session.bufferFrames) frames").font(.system(size: 10, design: .monospaced)).foregroundStyle(Noir.secondary)
        }.padding(18).modifier(GlassSurface(radius: 16))
    }
}
