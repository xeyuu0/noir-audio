// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AVFoundation
import CoreAudio
import UniformTypeIdentifiers

@MainActor final class StudioModel: ObservableObject {
    @Published var session: Session
    @Published var devices: [AudioDevice] = []
    @Published var running = false
    @Published var busy = false
    @Published var notice = "Choose your microphone and outputs, then start audio."
    @Published var error: String?
    let telemetry = EngineTelemetry()
    var peaks: [Float] { telemetry.snapshot.peaks }
    var rms: [Float] { telemetry.snapshot.rms }
    var waveform: [Float] { telemetry.snapshot.waveform }
    var cpu: Double { telemetry.snapshot.cpu }
    var latency: Double { telemetry.snapshot.latency }
    var underruns: UInt64 { telemetry.snapshot.underruns }
    var overruns: UInt64 { telemetry.snapshot.overruns }
    var clipped: UInt64 { telemetry.snapshot.clipped }
    @Published var recording = false
    @Published var recordingBusy = false
    @Published var recordStarted: Date?
    @Published var lastRecording: URL?
    @Published var exporting = false
    @Published var globalShortcutsActive = false
    @Published var shortcutStatus = "Shortcuts operate while NOIR is active."
    @Published var showSetup = false
    @Published var processes: [AudioProcess] = []
    @Published var selectedProcess: AudioObjectID = 0
    @Published var capturing = false
    @Published var playingClips = Set<Int>()
    @Published var loadingClips = false
    @Published var selectedSection: StudioSection = .dashboard
    let broadcast = BroadcastModel()
    let engine: NAEngine
    private var recorder: Recorder!
    private let tap = ApplicationTap()
    private var timer: Timer?
    private var tick = 0
    private var effectWork: DispatchWorkItem?
    private let preparation = DispatchQueue(label: "audio.noir.prepare", qos: .userInitiated)
    private var loadedClips = Set<Int>()
    private var queuedImports: [URL] = []
    private var recordingGeneration = 0
    private var audioGeneration = 0
    private var isShutdown = false
    private var desiredRunning = false
    private var setupPresented = false
    private let storageURL: URL
    private let shortcuts = GlobalShortcuts()

    init(storageURL: URL = SessionStore.url) {
        self.storageURL = storageURL
        engine = NACreate()!
        let saved = try? SessionStore.load(from: storageURL)
        session = saved ?? Session()
        devices = AudioHardware.devices()
        if saved == nil { session.channels[0].deviceUID = devices.first(where: { $0.id == AudioHardware.defaultInput })?.uid ?? "" }
        if saved == nil {
            session.clockUID = devices.first(where: { $0.id == AudioHardware.defaultOutput })?.uid ?? ""
            session.buses[1].deviceUID = session.clockUID
            session.buses[0].deviceUID = virtualMic?.uid ?? ""
        }
        recorder = Recorder(engine: engine, journalDirectory: storageURL.deletingLastPathComponent().appendingPathComponent("Recording Recovery"))
        recorder.onError = { [weak self] message in Task { @MainActor in self?.error = message; self?.recording = false; self?.recordingBusy = false; self?.recordStarted = nil } }
        recorder.setReplay(seconds: session.replaySeconds)
        recorder.recover { [weak self] result in Task { @MainActor in
            guard let self, !self.isShutdown else { return }
            switch result {
            case .success(let files): if let last = files.last { self.lastRecording = last; self.notice = "Recovered \(files.count) interrupted recording(s). Open Recorder to reveal the latest take." }
            case .failure(let error): self.error = "Recording recovery needs attention: \(error.localizedDescription)"
            }
        } }
        showSetup = false
        syncControls(); prepareEffects()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
        if !session.clips.isEmpty { reloadClips() }
        shortcuts.onAction = { [weak self] action in self?.perform(action) }
        updateShortcuts()
    }
    var keyboard: ShortcutPreferences { session.shortcuts ?? ShortcutPreferences() }
    func shortcut(_ action: StudioAction) -> StudioShortcut { keyboard.shortcut(action) }
    func perform(_ action: StudioAction) {
        guard !isShutdown else { return }
        switch action {
        case .audio: toggleAudio()
        case .mute: session.channels[0].mute.toggle(); syncControls()
        case .deafen: session.buses[1].mute.toggle(); syncControls()
        case .record: if recording { stopRecording() } else { startRecording() }
        case .replay: saveReplay()
        }
    }
    func updateShortcuts() {
        do { try shortcuts.configure(keyboard); globalShortcutsActive = keyboard.global; shortcutStatus = keyboard.global ? "Global shortcuts are active, including while another app is in front." : "Shortcuts operate while NOIR is active." }
        catch { globalShortcutsActive = false; shortcutStatus = error.localizedDescription }
    }
    func setShortcut(_ action: StudioAction, key: String? = nil, modifiers: ShortcutModifiers? = nil) {
        var preferences = keyboard; var selected = preferences.shortcut(action)
        if let key { selected.key = key }; if let modifiers { selected.modifiers = modifiers }
        preferences.actions[action.rawValue] = selected
        do { try preferences.validate(); session.shortcuts = preferences; updateShortcuts(); persist() } catch { self.error = error.localizedDescription }
    }
    func enableGlobalShortcuts(_ enabled: Bool) { var preferences = keyboard; preferences.global = enabled; session.shortcuts = preferences; updateShortcuts(); persist() }
    func presentFirstSetup() { guard !setupPresented else { return }; setupPresented = true; if !session.setupComplete { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showSetup = true } } }
    var virtualMic: AudioDevice? { devices.first { $0.name.hasPrefix("NOIR Microphone") } ?? devices.first { $0.name.contains("BlackHole") && $0.outputs == 2 } }
    var loopback: AudioDevice? { devices.first { $0.name.hasPrefix("NOIR Loopback") } ?? devices.first { $0.name.contains("BlackHole") && $0.inputs >= 16 } }
    var inputDevices: [AudioDevice] { devices.filter { $0.inputs > 0 && $0.id != tap.aggregate } }
    var outputDevices: [AudioDevice] { devices.filter { $0.outputs > 0 && $0.id != tap.aggregate } }
    func device(_ uid: String) -> AudioDevice? { devices.first { $0.uid == uid } }
    private func poll() {
        guard !isShutdown else { return }
        telemetry.poll(engine: engine, running: running)
        let playing = Set(session.clips.filter { NAClipPlaying(engine, Int32($0.id)) != 0 }.map(\.id))
        if playing != playingClips { playingClips = playing }
        NACollect(engine); tick += 1
        if tick % 60 == 0 { refreshDevices() }
    }
    func refreshDevices() {
        let next = AudioHardware.devices()
        let changed = next != devices
        if changed { devices = next }
        guard changed, desiredRunning, !busy else { return }
        let missing = session.channels.prefix(4).contains { !$0.deviceUID.isEmpty && device($0.deviceUID) == nil } || device(session.clockUID) == nil || session.buses.contains { !$0.deviceUID.isEmpty && device($0.deviceUID) == nil }
        if missing { if running { stopAudio(preserveIntent: true); notice = "An audio device disconnected. Routing is paused; reconnect it to recover." } }
        else { restartAudio() }
    }
    func syncControls() {
        for c in session.channels {
            NAChannel(engine, Int32(c.id), c.gain, c.volume, c.balance, c.mute ? 1 : 0, c.solo ? 1 : 0, c.effects ? 1 : 0)
            for b in 0..<4 {
                let feedback = c.id < 4 && !c.deviceUID.isEmpty && c.deviceUID == session.buses[b].deviceUID
                NARoute(engine, Int32(c.id), Int32(b), feedback ? 0 : c.sends[b])
            }
        }
        for b in session.buses { NABus(engine, Int32(b.id), b.volume, b.mute ? 1 : 0) }
        NARecordSource(engine, Int32(session.recordSource))
        persist()
    }
    func persist() { do { try SessionStore.save(session, to: storageURL) } catch { self.error = "Could not save settings: \(error.localizedDescription)" } }
    func prepareEffects() {
        effectWork?.cancel(); let settings = session.effects; let engine = engine
        let work = DispatchWorkItem { for i in 0..<6 { settings[i].values.withUnsafeBufferPointer { values in settings[i].order.withUnsafeBufferPointer { order in NASetEffects(engine, Int32(i), values.baseAddress, order.baseAddress) } } } }
        effectWork = work; preparation.asyncAfter(deadline: .now() + 0.15, execute: work)
        persist()
    }
    func toggleAudio() { if running { stopAudio() } else { startAudio() } }
    func startAudio() {
        guard !busy, !isShutdown else { return }; busy = true; desiredRunning = true
        audioGeneration += 1; let generation = audioGeneration
        if let issue = routingIssue() { busy = false; error = issue; return }
        Task {
            let usesInput = session.channels.prefix(4).contains { !$0.deviceUID.isEmpty }
            let allowed: Bool
            if usesInput { allowed = await AVCaptureDevice.requestAccess(for: .audio) } else { allowed = true }
            guard !isShutdown, generation == audioGeneration, desiredRunning else { return }
            guard allowed else { busy = false; desiredRunning = false; error = "Microphone access is off. Enable NOIR Audio in System Settings → Privacy & Security → Microphone, then start audio again."; return }
            startAuthorized()
        }
    }
    private func routingIssue() -> String? {
        guard let clock = device(session.clockUID), clock.outputs > 0 else { return "Select an available clock / headphone output in Settings." }
        for channel in session.channels.prefix(4) where !channel.deviceUID.isEmpty {
            guard let selected = device(channel.deviceUID), selected.inputs > channel.pair * 2 else { return "\(channel.name)'s selected input is unavailable. Reconnect it or choose an available input/channel pair in Audio Mixer." }
        }
        for bus in session.buses where !bus.deviceUID.isEmpty {
            guard let selected = device(bus.deviceUID), selected.outputs > bus.pair * 2 else { return "\(bus.name)'s selected output is unavailable. Reconnect it or choose an available output/channel pair in Audio Mixer." }
        }
        return nil
    }
    private func startAuthorized() {
        guard !isShutdown else { return }
        if let issue = routingIssue() { busy = false; error = issue; return }
        let ids = session.channels.prefix(4).map { device($0.deviceUID)?.id ?? 0 } + [tap.aggregate]
        let pairs = session.channels.prefix(4).map { Int32($0.pair) } + [Int32(0)]
        let outputs = session.buses.map { device($0.deviceUID)?.id ?? 0 }, outputPairs = session.buses.map { Int32($0.pair) }
        guard let clock = device(session.clockUID) else { busy = false; error = "Select an available clock / headphone output in Settings."; return }
        syncControls()
        let result = NAStart(engine, ids, pairs, outputs, outputPairs, clock.id, Int32(session.bufferFrames))
        busy = false; running = result == 0
        if result != 0 { error = String(cString: NAError(engine)); desiredRunning = false }
        else { notice = "Audio is running. Main feeds your virtual microphone; Monitor is independent." }
    }
    func stopAudio(preserveIntent: Bool = false) {
        audioGeneration += 1; busy = false
        if !preserveIntent { desiredRunning = false }
        broadcast.stop(); NAStopClips(engine); NAStop(engine); running = false; stopRecording(); notice = "Audio stopped."
    }
    func restartAudio() { guard desiredRunning || running else { persist(); return }; NAStop(engine); running = false; startAuthorized() }
    func routingChanged() { syncControls(); if running { restartAudio() } }
    func setRoute(source: Int, bus: Int, on: Bool) {
        let c = session.channels[source], b = session.buses[bus]
        guard !(on && source < 4 && !c.deviceUID.isEmpty && c.deviceUID == b.deviceUID) else { error = "Feedback prevented: \(c.name) cannot return to its own input device. Send it to a different bus."; return }
        session.channels[source].sends[bus] = on ? 1 : 0; syncControls()
    }
    func preset(_ name: String) { session.applyPreset(name); prepareEffects(); syncControls(); notice = "Loaded \(name). Monitoring stays off until you enable its sends." }
    func testOutput() {
        guard running else { error = "Start audio before testing the output."; return }
        guard !session.buses[1].deviceUID.isEmpty else { error = "Choose a Monitor output in Audio Mixer."; return }
        NATestTone(engine, 1); notice = "Playing a two-second 440 Hz test tone at −30 dBFS through Monitor."
    }
    func refreshProcesses() { processes = ApplicationTap.processes() }
    func startCapture() {
        guard selectedProcess != 0 else { return }
        let wasRunning = running; NAStop(engine); running = false
        do { try tap.create(process: selectedProcess); capturing = true; if wasRunning { startAuthorized() }; notice = "Application capture is active. Enable the Application sends in the routing matrix." }
        catch { tap.destroy(); capturing = false; self.error = error.localizedDescription; if wasRunning { startAuthorized() } }
    }
    func stopCapture() { let wasRunning = running; NAStop(engine); running = false; tap.destroy(); capturing = false; if wasRunning { startAuthorized() } }
    func importClips(urls: [URL]? = nil, replacing slot: Int? = nil) {
        var files = urls
        if files == nil { let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = true; panel.message = "Import audio clips (up to five minutes each)."; guard panel.runModal() == .OK else { return }; files = panel.urls }
        guard let files, !files.isEmpty, !isShutdown else { return }
        if loadingClips { if slot == nil { queuedImports += files }; return }
        loadingClips = true
        let used = Set(session.clips.map(\.id)); let available = (0..<48).filter { !used.contains($0) }
        let jobs = slot.map { [($0, files[0])] } ?? Array(zip(available, files)); let engine = engine
        guard !jobs.isEmpty else { loadingClips = false; error = "All 48 pads are occupied. Remove or replace a clip to import more audio."; return }
        let directory = storageURL.deletingLastPathComponent().appendingPathComponent("Clips", isDirectory: true)
        let truncated = slot == nil && jobs.count < files.count
        preparation.async { [weak self] in
            var imported: [ClipState] = []; var failures: [String] = []
            for (slot, file) in jobs {
                let owned = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(file.pathExtension)
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: file, to: owned)
                    let data = try ClipDecoder.decode(owned)
                    guard NALoadClip(engine, Int32(slot), data, Int32(data.count / 2)) == 0 else { throw NoirError.message("The 256 MB soundboard memory limit was reached.") }
                    imported.append(ClipState(id: slot, name: file.deletingPathExtension().lastPathComponent, path: owned.path))
                } catch { try? FileManager.default.removeItem(at: owned); failures.append(error.localizedDescription) }
            }
            Task { @MainActor in
                guard let self, !self.isShutdown else { return }
                for clip in imported {
                    if let index = self.session.clips.firstIndex(where: { $0.id == clip.id }) {
                        let old = self.session.clips[index]; var replacement = clip
                        replacement.volume = old.volume; replacement.loop = old.loop; replacement.fade = old.fade
                        self.session.clips[index] = replacement; self.removeOwnedClipFile(old)
                    } else { self.session.clips.append(clip) }
                }
                self.session.clips.sort { $0.id < $1.id }; self.loadedClips.formUnion(imported.map(\.id)); self.loadingClips = false; self.persist()
                if !failures.isEmpty { self.error = failures.joined(separator: "\n") }
                if truncated { self.notice = "Imported the available pads. The soundboard is full." }
                self.continueImports()
            }
        }
    }
    private func continueImports() { guard !queuedImports.isEmpty else { return }; let files = queuedImports; queuedImports = []; importClips(urls: files) }
    private func removeOwnedClipFile(_ clip: ClipState) {
        let file = URL(fileURLWithPath: clip.path).standardizedFileURL
        let ownedDirectory = storageURL.deletingLastPathComponent().appendingPathComponent("Clips").standardizedFileURL
        if file.deletingLastPathComponent() == ownedDirectory { preparation.async { try? FileManager.default.removeItem(at: file) } }
    }
    func removeClip(_ clip: ClipState) {
        guard !loadingClips, !isShutdown else { return }
        let engine = engine; preparation.async { NAUnloadClip(engine, Int32(clip.id)) }
        loadedClips.remove(clip.id); session.clips.removeAll { $0.id == clip.id }; removeOwnedClipFile(clip); persist()
    }
    private func reloadClips() {
        loadingClips = true
        let clips = session.clips, engine = engine
        preparation.async { [weak self] in
            var loaded = Set<Int>(), failures: [String] = []
            for clip in clips {
                do { let data = try ClipDecoder.decode(URL(fileURLWithPath: clip.path)); if NALoadClip(engine, Int32(clip.id), data, Int32(data.count / 2)) == 0 { loaded.insert(clip.id) } }
                catch { failures.append("\(clip.name): \(error.localizedDescription)") }
            }
            Task { @MainActor in guard let self, !self.isShutdown else { return }; self.loadedClips = loaded; self.loadingClips = false; if !failures.isEmpty { self.notice = "Some soundboard files are unavailable. Replace those clips or restore their original locations." }; self.continueImports() }
        }
    }
    func play(_ clip: ClipState) {
        guard running else { error = "Start audio before playing soundboard clips."; return }
        guard loadedClips.contains(clip.id) else { error = "This clip is unavailable. Restore the audio file at \(clip.path)."; return }
        NAPlayClip(engine, Int32(clip.id), clip.volume, clip.loop ? 1 : 0, clip.fade)
    }
    func stopAllClips() { NAStopClips(engine) }
    func chooseRecordingFolder() { let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; guard panel.runModal() == .OK, let url = panel.url else { return }; session.recordingFolder = url.path; persist() }
    private func recordingURL(prefix: String) throws -> URL {
        let folder = session.recordingFolder.isEmpty ? FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent("NOIR Recordings") : URL(fileURLWithPath: session.recordingFolder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return folder.appendingPathComponent("\(prefix) \(formatter.string(from: Date()))-\(UUID().uuidString.prefix(4)).wav")
    }
    func startRecording() {
        guard running, !recording, !recordingBusy, !isShutdown else { return }
        recordingGeneration += 1; let generation = recordingGeneration; recordingBusy = true
        do { let url = try recordingURL(prefix: "NOIR"); recorder.start(url: url) { [weak self] result in Task { @MainActor in
            guard let self, !self.isShutdown, self.recordingGeneration == generation else { return }
            self.recordingBusy = false
            switch result { case .success: self.recording = true; self.recordStarted = Date(); self.lastRecording = url; case .failure(let error): self.error = error.localizedDescription }
        } } } catch { recordingBusy = false; self.error = error.localizedDescription }
    }
    func stopRecording() {
        guard recording || recordingBusy else { return }
        recordingGeneration += 1; let generation = recordingGeneration
        recording = false; recordingBusy = true; recordStarted = nil
        recorder.stop { [weak self] result in Task { @MainActor in
            guard let self, !self.isShutdown, self.recordingGeneration == generation else { return }; self.recordingBusy = false
            switch result { case .success: self.notice = "Recording saved as a 24-bit WAV."; case .failure(let error): self.error = "Could not finish the recording: \(error.localizedDescription). The unfinished take is retained for recovery." }
        } }
    }
    func exportRecording() {
        guard let input = lastRecording, !recording, !recordingBusy, !exporting else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Audio]; panel.nameFieldStringValue = input.deletingPathExtension().lastPathComponent + ".m4a"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        exporting = true
        preparation.async { [weak self] in
            let result = Result { try AudioExport.aac(input: input, destination: destination) }
            Task { @MainActor in guard let self, !self.isShutdown else { return }; self.exporting = false; switch result { case .success: self.notice = "Exported \(destination.lastPathComponent) as AAC at 192 kbps."; case .failure(let error): self.error = error.localizedDescription } }
        }
    }
    func saveReplay() {
        do { let url = try recordingURL(prefix: "NOIR Replay"); recorder.saveReplay(url: url) { [weak self] result in Task { @MainActor in
            switch result { case .success: self?.lastRecording = url; self?.notice = "Replay saved to \(url.lastPathComponent)."; case .failure(let error): self?.error = error.localizedDescription }
        } } } catch { self.error = error.localizedDescription }
    }
    func replayChanged() { recorder.setReplay(seconds: session.replaySeconds); persist() }
    func recordSourceChanged() { recorder.clearReplay(); syncControls() }
    func savePreset() { let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "\(session.name).json"; guard panel.runModal() == .OK, let url = panel.url else { return }; do { try SessionStore.save(session, to: url) } catch { self.error = error.localizedDescription } }
    func loadPreset() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let next = try SessionStore.load(from: url); let clips = session.clips, keyboard = session.shortcuts; session = next; session.clips = clips; session.shortcuts = keyboard; prepareEffects(); syncControls(); restartAudio() } catch { self.error = error.localizedDescription }
    }
    func resetAudio() { stopAudio(); session.applyPreset("Clean Microphone"); session.channels[0].deviceUID = devices.first(where: { $0.id == AudioHardware.defaultInput })?.uid ?? ""; session.clockUID = devices.first(where: { $0.id == AudioHardware.defaultOutput })?.uid ?? ""; session.buses[0].deviceUID = virtualMic?.uid ?? ""; session.buses[1].deviceUID = session.clockUID; for i in 1..<4 { session.channels[i].deviceUID = "" }; session.buses[2].deviceUID = ""; session.buses[3].deviceUID = ""; prepareEffects(); syncControls() }
    func shutdown() { guard !isShutdown else { return }; isShutdown = true; shortcuts.shutdown(); timer?.invalidate(); effectWork?.cancel(); preparation.sync {}; broadcast.shutdown(); NAStop(engine); recorder.shutdown(); tap.destroy(); persist(); NADestroy(engine) }
}
