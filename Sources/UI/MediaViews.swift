// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio

struct SoundboardView: View {
    @EnvironmentObject var model: StudioModel
    @State private var page = 0
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
        HStack { Picker("Page", selection: $page) { ForEach(0..<4) { Text("Page \($0 + 1)").tag($0) } }.pickerStyle(.segmented).frame(width: 340); Spacer(); Button("Stop all", action: model.stopAllClips); Button(model.loadingClips ? "Importing…" : "Import audio…") { model.importClips() }.disabled(model.loadingClips) }.buttonStyle(SecondaryButtonStyle())
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
            ForEach(Array(model.session.clips.filter { $0.page == page }.enumerated()), id: \.element.id) { index, clip in
                Panel(title: "", subtitle: "") {
                    HStack { Tag(text: String(format: "%02d", clip.id + 1), active: model.playingClips.contains(clip.id)); Spacer(); Image(systemName: model.playingClips.contains(clip.id) ? "waveform" : "waveform.path") }
                    TextField("Clip name", text: clipBinding(clip, \.name)).font(.system(size: 16, weight: .medium)).textFieldStyle(.plain)
                    Button { model.play(clip) } label: { Label(model.playingClips.contains(clip.id) ? "Retrigger" : "Play clip", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle()).modifier(PadShortcut(index: index))
                    ValueSlider(title: "Volume", value: clipBinding(clip, \.volume), range: 0...1.5, step: 0.01)
                    ValueSlider(title: "Fade in / out", value: clipBinding(clip, \.fade), range: 0...2, unit: " s", step: 0.01)
                    Toggle("Loop", isOn: clipBinding(clip, \.loop)).toggleStyle(.checkbox)
                    HStack { Button("Replace…") { model.importClips(replacing: clip.id) }; Spacer(); Button("Remove") { model.removeClip(clip) } }.buttonStyle(.borderless).disabled(model.loadingClips)
                }
            }
        }
        if model.session.clips.filter({ $0.page == page }).isEmpty {
            Panel(title: "Make some room for sound.") {
                VStack(spacing: 18) { Image(systemName: "waveform.badge.plus").font(.system(size: 36, weight: .ultraLight)); Text("Drop audio files here").font(.system(size: 18)); Text("WAV, AIFF, MP3, M4A and other formats supported by macOS.\n48 pads across four pages · up to five minutes per clip.").multilineTextAlignment(.center).font(.system(size: 12)).foregroundStyle(Noir.secondary); Button("Choose audio files…") { model.importClips() }.buttonStyle(SecondaryButtonStyle()) }.frame(maxWidth: .infinity).padding(.vertical, 50)
            }
        }
        Panel(title: "Soundboard routing") {
            HStack { ForEach(0..<4) { b in Toggle(model.session.buses[b].name, isOn: Binding(get: { model.session.channels[4].sends[b] > 0 }, set: { model.setRoute(source: 4, bus: b, on: $0) })).toggleStyle(.checkbox); Spacer() } }
            Text("Main can feed your virtual microphone; Monitor feeds headphones independently. ⌥⌘1–9 triggers the first nine pads visible on the current page. Escape stops all clips.").font(.system(size: 11)).foregroundStyle(Noir.secondary)
        }
        }
        .overlay { if targeted { RoundedRectangle(cornerRadius: 14).stroke(.white, lineWidth: 2).allowsHitTesting(false) } }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { continuation in _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) } }
                    if let url { urls.append(url) }
                }
                model.importClips(urls: urls)
            }
            return true
        }
    }
    private func clipBinding<T>(_ clip: ClipState, _ key: WritableKeyPath<ClipState, T>) -> Binding<T> {
        Binding(get: { (model.session.clips.first(where: { $0.id == clip.id }) ?? clip)[keyPath: key] }, set: { value in if let i = model.session.clips.firstIndex(where: { $0.id == clip.id }) { model.session.clips[i][keyPath: key] = value; model.persist() } })
    }
}
private struct PadShortcut: ViewModifier {
    let index: Int
    @ViewBuilder func body(content: Content) -> some View {
        if index < 9 { content.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option]) }
        else { content }
    }
}
struct CaptureView: View {
    @EnvironmentObject var model: StudioModel
    @EnvironmentObject var telemetry: EngineTelemetry
    var body: some View {
        Panel(title: "Application source", subtitle: model.capturing ? "CAPTURING" : "OFF") {
            Text("Capture one application's output with a private Core Audio process tap. macOS will request System Audio Recording permission. The application's normal playback remains audible.").font(.system(size: 13)).foregroundStyle(Noir.secondary)
            HStack { Picker("Application", selection: $model.selectedProcess) { Text("Choose an application").tag(AudioObjectID(0)); ForEach(model.processes) { Text($0.name).tag($0.id) } }.frame(maxWidth: 420); Button("Refresh", action: model.refreshProcesses); Spacer() }
            HStack { Button(model.capturing ? "Stop capture" : "Start selected capture") { model.capturing ? model.stopCapture() : model.startCapture() }.disabled(!model.capturing && model.selectedProcess == 0); Button("Recording permissions") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) } }.buttonStyle(SecondaryButtonStyle())
            MeterView(peak: model.peaks[5], rms: model.rms[5], label: "APPLICATION INPUT")
            HStack { ForEach(0..<4) { b in Toggle(model.session.buses[b].name, isOn: Binding(get: { model.session.channels[5].sends[b] > 0 }, set: { model.setRoute(source: 5, bus: b, on: $0) })).toggleStyle(.checkbox); Spacer() } }
        }.onAppear(perform: model.refreshProcesses)
        Panel(title: "Keep your mix clean") {
            Text("Choose a music player, browser, or Logic Pro as the source. Avoid capturing the voice-chat application you are sending Main into; that creates a return loop. Protected content may be silent. If an application uses several helper processes, use a dedicated loopback device for its complete output.").foregroundStyle(Noir.secondary)
            Text("Logic Pro: choose NOIR Loopback as Logic's output device, then choose NOIR Loopback on a NOIR input strip. Send that strip to Main and Monitor. Set your chat application's microphone to NOIR Microphone. Never return that strip to NOIR Loopback.").foregroundStyle(Noir.secondary)
        }.font(.system(size: 13))
    }
}
struct RecorderView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View {
        Panel(title: "Recorder", subtitle: "WAV  /  24-BIT  /  48 kHz") {
            HStack(alignment: .center, spacing: 30) {
                Image(systemName: model.recording ? "record.circle.fill" : "record.circle").font(.system(size: 48, weight: .ultraLight))
                VStack(alignment: .leading, spacing: 8) { Text(model.recording ? "Recording your take" : "Ready when you are").font(.system(size: 24, weight: .light)); if let started = model.recordStarted { Text(started, style: .timer).monospacedDigit() } else { Text("Files are written safely outside the audio callback.").font(.system(size: 12)).foregroundStyle(Noir.secondary) } }
                Spacer()
                Button(model.recordingBusy ? "Finishing…" : model.recording ? "Stop & save" : "Start recording") { model.recording ? model.stopRecording() : model.startRecording() }.disabled(!model.running || model.recordingBusy).buttonStyle(SecondaryButtonStyle())
            }
            Picker("Record source", selection: model.binding(\.recordSource, update: model.recordSourceChanged)) { Text("Main mix").tag(0); Text("Monitor mix").tag(1); Text("Aux 2").tag(2); Text("Aux 3").tag(3); Text("Microphone before effects").tag(4); Text("Processed microphone").tag(5) }.disabled(model.recording || model.recordingBusy)
            HStack { Text(model.session.recordingFolder.isEmpty ? "Music / NOIR Recordings" : model.session.recordingFolder).font(.system(size: 12)).foregroundStyle(Noir.secondary).lineLimit(2); Spacer(); Button("Choose destination…", action: model.chooseRecordingFolder) }
        }
        Panel(title: "Instant replay", subtitle: "ALWAYS BUFFERING WHILE AUDIO RUNS") {
            HStack { Picker("Keep the last", selection: model.binding(\.replaySeconds, update: model.replayChanged)) { ForEach([5, 15, 30, 60, 120], id: \.self) { Text("\($0) seconds").tag($0) } }.frame(width: 240); Spacer(); Button("Save replay", action: model.saveReplay).disabled(!model.running) }
            Text("Replay follows the selected recording source. Changing its duration or source clears the previous buffer. Audio stays in memory until you save it.").font(.system(size: 12)).foregroundStyle(Noir.secondary)
        }
        if let url = model.lastRecording { Panel(title: "Latest recording") { HStack { Label(url.lastPathComponent, systemImage: "waveform").font(.system(size: 12)); Spacer(); Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }; Button("Play") { NSWorkspace.shared.open(url) }.disabled(model.recording || model.recordingBusy); Button(model.exporting ? "Exporting…" : "Export AAC…", action: model.exportRecording).disabled(model.recording || model.recordingBusy || model.exporting) } } }
    }
}
struct BroadcastView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View { BroadcastControls(broadcast: model.broadcast, engine: model.engine, running: model.running, buses: model.session.buses) }
}
struct BroadcastControls: View {
    @ObservedObject var broadcast: BroadcastModel
    var engine: NAEngine
    var running: Bool
    var buses: [BusState]
    var body: some View {
        Panel(title: "Stream connection", subtitle: broadcast.active ? "ENCODER ACTIVE" : "OFFLINE") {
            Text(broadcast.status).font(.system(size: 13)).textSelection(.enabled)
            Form {
                Picker("Protocol", selection: $broadcast.config.kind) { ForEach(StreamProtocol.allCases) { Text($0.rawValue).tag($0) } }
                TextField("Server / mount / stream URL", text: $broadcast.config.endpoint)
                if broadcast.config.kind != .rtmp { TextField("Source username", text: $broadcast.config.username); SecureField("Source password", text: $broadcast.config.password) }
                TextField("Stream title", text: $broadcast.config.title)
                Picker("Broadcast mix", selection: $broadcast.config.bus) { ForEach(buses) { Text($0.name).tag($0.id) } }
                Picker("Codec", selection: $broadcast.config.codec) { ForEach(StreamCodec.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Bitrate", selection: $broadcast.config.bitrate) { ForEach([64, 96, 128, 192, 256, 320], id: \.self) { Text("\($0) kbps").tag($0) } }
                Toggle("Reconnect automatically (up to eight retries)", isOn: $broadcast.config.reconnect)
            }.disabled(broadcast.active)
            HStack { Button(broadcast.active ? "Disconnect" : "Connect stream") { broadcast.active ? broadcast.stop() : broadcast.start(engine: engine) }.disabled(!broadcast.active && (!running || !broadcast.available)); Spacer(); Text("\(broadcast.seconds)s  ·  \(ByteCountFormatter.string(fromByteCount: Int64(broadcast.bytes), countStyle: .file)) PCM to encoder").font(.system(size: 11, design: .monospaced)).foregroundStyle(Noir.secondary) }
        }
        Panel(title: "Encoder") {
            InfoRow(title: "FFmpeg", value: broadcast.available ? broadcast.config.executable : "Not installed / selected")
            Button("Choose FFmpeg executable…", action: broadcast.chooseEncoder).disabled(broadcast.active)
            HStack {
                Button("Custom certificate authority…", action: broadcast.chooseCertificateAuthority)
                if !broadcast.config.certificateAuthority.isEmpty {
                    Text(URL(fileURLWithPath: broadcast.config.certificateAuthority).lastPathComponent).font(.system(size: 11)).lineLimit(1)
                    Button("Use default trust") { broadcast.config.certificateAuthority = "" }
                }
            }.disabled(broadcast.active)
            Text("Secure Icecast and RTMPS verify the server certificate and hostname. Select a custom PEM authority only for a private server you trust.").font(.system(size: 11)).foregroundStyle(Noir.secondary)
            Text("Use an FFmpeg build with native AAC, libmp3lame and libopus. RTMP uses AAC in FLV; some video services require a video track and will reject an audio-only stream. Server reception must be checked at your receiver. Credentials stay in memory and are never written to NOIR logs; they are passed to the local encoder process.").font(.system(size: 12)).foregroundStyle(Noir.secondary)
        }
    }
}
