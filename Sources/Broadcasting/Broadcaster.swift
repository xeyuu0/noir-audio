// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Combine
import AppKit
import Darwin

enum StreamProtocol: String, CaseIterable, Identifiable { case icecast = "Icecast", shoutcast = "SHOUTcast", rtmp = "RTMP / RTMPS"; var id: String { rawValue } }
enum StreamCodec: String, CaseIterable, Identifiable { case aac = "AAC", mp3 = "MP3", opus = "Opus"; var id: String { rawValue } }

struct BroadcastConfiguration {
    var executable = "/opt/homebrew/bin/ffmpeg"
    var kind = StreamProtocol.icecast
    var codec = StreamCodec.mp3
    var endpoint = ""
    var username = "source"
    var password = ""
    var title = "NOIR Audio"
    var bitrate = 128
    var bus = 3
    var reconnect = true
    var certificateAuthority = ""
    func arguments() throws -> [String] {
        guard var url = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme?.lowercased(), url.host != nil else { throw NoirError.message("Enter a complete stream URL, including its protocol and mount or stream key.") }
        guard (0..<4).contains(bus), [64,96,128,192,256,320].contains(bitrate), !title.utf8.contains(13), !title.utf8.contains(10) else { throw NoirError.message("Choose a valid broadcast bus, bitrate and single-line title.") }
        var output = endpoint.trimmingCharacters(in: .whitespacesAndNewlines), extra: [String] = [], format = "mp3", encoder = "libmp3lame"
        switch kind {
        case .icecast:
            guard ["icecast", "icecasts"].contains(scheme) else { throw NoirError.message("Icecast requires icecast://host:port/mount or icecasts://host:port/mount.") }
            guard !url.path.isEmpty, url.path != "/" else { throw NoirError.message("Include an Icecast mount path, such as /live.mp3.") }
            url.user = username; url.password = password
            if scheme == "icecasts" {
                // FFmpeg's icecast wrapper discards TLS verification/CA options.
                // Its underlying HTTP PUT transport exposes them directly.
                url.scheme = "https"
                extra += ["-method", "PUT", "-auth_type", "basic", "-chunked_post", "0", "-send_expect_100", "1",
                          "-headers", "Ice-Name: \(title)\r\nIce-Public: 0\r\n", "-tls_verify", "1", "-verifyhost", url.host!]
            } else { url.scheme = "icecast"; extra += ["-ice_name", title] }
            output = url.string!
            extra += ["-content_type", codec == .mp3 ? "audio/mpeg" : codec == .opus ? "audio/ogg" : "audio/aac"]
        case .shoutcast:
            guard scheme == "shoutcast", codec == .mp3 else { throw NoirError.message("SHOUTcast v1 uses shoutcast://host:source-port and MP3. Use the server's source port, commonly listener port + 1.") }
            output = "pipe:1"
        case .rtmp:
            guard ["rtmp", "rtmps"].contains(scheme), codec == .aac else { throw NoirError.message("RTMP requires an rtmp:// or rtmps:// URL and AAC audio.") }
            format = "flv"
            if scheme == "rtmps" { extra += ["-tls_verify", "1", "-verifyhost", url.host!] }
        }
        switch codec { case .aac: encoder = "aac"; if kind != .rtmp { format = "adts" }; case .mp3: encoder = "libmp3lame"; case .opus: encoder = "libopus"; format = "ogg" }
        if !certificateAuthority.isEmpty && ["icecasts", "rtmps"].contains(scheme) { extra += ["-ca_file", certificateAuthority] }
        return ["-hide_banner", "-loglevel", "error", "-nostdin", "-f", "f32le", "-ar", "48000", "-ac", "2", "-i", "pipe:0", "-vn", "-c:a", encoder, "-b:a", "\(bitrate)k", "-metadata", "title=\(title)", "-rw_timeout", "5000000"] + extra + ["-f", format, output]
    }
}

@MainActor final class BroadcastModel: ObservableObject {
    @Published var config = BroadcastConfiguration()
    @Published var status = "Offline"
    @Published var active = false
    @Published var seconds = 0
    @Published var bytes: UInt64 = 0
    private let worker = DispatchQueue(label: "audio.noir.broadcast", qos: .utility)
    private let forwarding = DispatchQueue(label: "audio.noir.broadcast.forward", qos: .utility)
    private var shoutcast: ShoutcastConnection?
    private var process: Process?
    private var input: EncoderInput?
    private var timer: DispatchSourceTimer?
    private var engine: NAEngine?
    private var generation = 0
    private var attempts = 0
    private var started: Date?
    private var written: UInt64 = 0
    private var pendingError = ""
    init() { signal(SIGPIPE, SIG_IGN) }
    var available: Bool { FileManager.default.isExecutableFile(atPath: config.executable) }
    func chooseEncoder() { let panel = NSOpenPanel(); panel.message = "Select an FFmpeg executable with AAC, MP3, and Opus encoders."; panel.showsHiddenFiles = true; guard panel.runModal() == .OK, let url = panel.url else { return }; config.executable = url.path }
    func chooseCertificateAuthority() {
        let panel = NSOpenPanel(); panel.message = "Select a PEM certificate authority bundle for your private TLS server. Public servers normally use the encoder's default trust store."
        guard panel.runModal() == .OK, let url = panel.url else { return }; config.certificateAuthority = url.path
    }
    func start(engine: NAEngine) {
        guard available else { status = "Choose an installed FFmpeg executable first."; return }
        do { _ = try config.arguments() } catch { status = error.localizedDescription; return }
        stop(); self.engine = engine; active = true; started = Date(); written = 0; bytes = 0; seconds = 0; attempts = 0; generation += 1; connect(generation)
    }
    private func connect(_ token: Int) {
        guard active, generation == token else { return }
        status = attempts == 0 ? "Connecting…" : "Reconnecting (attempt \(attempts + 1))…"
        if config.kind == .shoutcast {
            do {
                let transport = try ShoutcastConnection(configuration: config); shoutcast = transport
                transport.connect { [weak self] result in Task { @MainActor in
                    guard let self, self.generation == token, self.active, self.shoutcast === transport else { return }
                    switch result {
                    case .success: self.launch(token, transport: transport)
                    case .failure(let error): self.pendingError = error.localizedDescription; self.terminated(token, code: -1)
                    }
                } }
            } catch { pendingError = error.localizedDescription; terminated(token, code: -1) }
        } else { launch(token, transport: nil) }
    }
    private func launch(_ token: Int, transport: ShoutcastConnection?) {
        guard active, generation == token, let engine else { return }
        let child = Process(), pipe = Pipe(), errors = Pipe(), encoded = Pipe()
        do { child.executableURL = URL(fileURLWithPath: config.executable); child.arguments = try config.arguments() } catch { status = error.localizedDescription; active = false; return }
        child.standardInput = pipe; child.standardError = errors; child.standardOutput = transport == nil ? FileHandle.nullDevice : encoded as Any
        pendingError = ""; status = attempts == 0 ? "Connecting…" : "Reconnecting (attempt \(attempts + 1))…"
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            // Encoder diagnostics may contain stream credentials. Never surface raw stderr.
            Task { @MainActor in self?.pendingError = "The encoder or server rejected the stream. Check URL, credentials, codec, and server availability." }
        }
        child.terminationHandler = { [weak self] task in Task { @MainActor in guard let self, self.process === task else { return }; self.terminated(token, code: task.terminationStatus) } }
        do { try child.run() } catch { status = "Could not launch FFmpeg: \(error.localizedDescription)"; active = false; return }
        // Parent copies of child-only pipe ends would prevent EOF after exit.
        try? pipe.fileHandleForReading.close(); try? errors.fileHandleForWriting.close(); try? encoded.fileHandleForWriting.close()
        let pump: EncoderInput
        do { pump = try EncoderInput(pipe.fileHandleForWriting) }
        catch { child.terminate(); status = error.localizedDescription; active = false; return }
        process = child; input = pump
        if let transport {
            forwarding.async {
                do { while let data = try encoded.fileHandleForReading.read(upToCount: 8192), !data.isEmpty { try transport.write(data) } }
                catch { if child.isRunning { child.terminate() } }
                try? encoded.fileHandleForReading.close()
            }
        }
        // Consume queued samples from an earlier connection before resuming the producer.
        worker.sync { var discarded = [Float](repeating: 0, count: 8192); while NAReadBroadcast(engine, &discarded, 4096) > 0 {} }
        NABroadcast(engine, Int32(config.bus), 1)
        let source = DispatchSource.makeTimerSource(queue: worker)
        var lastUpdate = Date(), sent: UInt64 = 0
        source.schedule(deadline: .now(), repeating: .milliseconds(10))
        source.setEventHandler { [weak self] in
            var data = [Float](repeating: 0, count: 8192)
            let frames = Int(NAReadBroadcast(engine, &data, 4096))
            do {
                let count = try data.withUnsafeBytes { bytes in try pump.append(Data(bytes: bytes.baseAddress!, count: frames * 8)) }; sent += UInt64(count)
                if Date().timeIntervalSince(lastUpdate) >= 0.25 {
                    let completed = sent; sent = 0; lastUpdate = Date()
                    Task { @MainActor in guard let self, self.generation == token, self.process === child else { return }; self.written += completed; self.bytes = self.written; self.seconds = Int(Date().timeIntervalSince(self.started ?? Date())); if self.seconds >= 2 { self.status = "Sending audio · server reception unverified" } }
                }
            } catch { if child.isRunning { child.terminate() } }
        }
        timer = source; source.resume()
    }
    private func terminated(_ token: Int, code: Int32) {
        guard token == generation, active else { return }; timer?.cancel(); timer = nil; let oldInput = input; worker.sync { oldInput?.close() }; input = nil; process = nil; shoutcast?.cancel(); shoutcast = nil
        if let engine { NABroadcast(engine, Int32(config.bus), 0) }
        if config.reconnect && attempts < 8 { attempts += 1; status = "Connection lost. Retrying in \(min(30, attempts * 3)) seconds…"; DispatchQueue.main.asyncAfter(deadline: .now() + Double(min(30, attempts * 3))) { [weak self] in self?.connect(token) } }
        else { active = false; status = pendingError.isEmpty ? "Stream ended (encoder exit \(code))." : pendingError }
    }
    func stop() {
        generation += 1; active = false; if let engine { NABroadcast(engine, Int32(config.bus), 0) }
        timer?.cancel(); timer = nil; shoutcast?.cancel(); shoutcast = nil
        let oldInput = input; worker.sync { oldInput?.close() }; input = nil
        if let child = process {
            child.terminationHandler = nil
            if child.isRunning { child.terminate() }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { if child.isRunning { kill(child.processIdentifier, SIGKILL) } }
        }
        process = nil; status = "Offline"
    }
    func shutdown() { stop(); worker.sync {}; forwarding.sync {}; engine = nil }
}
