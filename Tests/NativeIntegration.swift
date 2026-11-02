// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import AVFoundation
import CoreAudio

@main struct NativeIntegration {
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ okay: Bool, _ name: String) { print("\(okay ? "PASS" : "FAIL") \(name)"); if !okay { failures += 1 } }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/Results")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let all = AudioHardware.devices()
        for device in all { print("DEVICE \(device.name) | \(device.inputs) input, \(device.outputs) output | \(device.rate) Hz | \(device.buffer) frames") }
        check(!all.isEmpty, "Enumerates real Core Audio devices")
        let engine = NACreate()!
        let recorder = Recorder(engine: engine, journalDirectory: root.appendingPathComponent("Native Recovery"))
        let output = root.appendingPathComponent("native-callback-recording.wav")
        try? FileManager.default.removeItem(at: output)
        let originalBuffer = all.first(where: { $0.id == AudioHardware.defaultOutput })?.buffer ?? 256
        let started: Result<Void, Error> = await withCheckedContinuation { continuation in recorder.start(url: output) { continuation.resume(returning: $0) } }
        try started.get()
        // Clock a real HAL device, but send only silence to hardware. The test tone is
        // routed to the disconnected Main bus and recorded; no microphone is opened.
        let status = NAStart(engine, [0,0,0,0,0], [0,0,0,0,0], [0,0,0,0], [0,0,0,0], AudioHardware.defaultOutput, Int32(originalBuffer))
        check(status == 0, "Starts actual HAL output callbacks with silent hardware output")
        if status != 0 { print(String(cString: NAError(engine))); recorder.shutdown(); NADestroy(engine); exit(1) }
        NATestTone(engine, 0)
        try await Task.sleep(for: .seconds(3))
        let stopped: Result<Void, Error> = await withCheckedContinuation { c in recorder.stop { c.resume(returning: $0) } }
        try stopped.get()
        let file = try AVAudioFile(forReading: output)
        check(file.length > 48000 * 2 && file.length < 48000 * 4 && file.fileFormat.channelCount == 2 && file.fileFormat.sampleRate == 48000, "Real HAL clock produces a correctly timed 48 kHz stereo WAV")
        let decoded = try ClipDecoder.decode(output)
        let peak = decoded.map { abs($0) }.max() ?? 0
        check(peak > 0.02 && peak < 0.04, "Recorded tone amplitude matches the −30 dBFS source")
        check(decoded.contains(where: { abs($0) > 0.01 }), "Native decoder reads actual recorded audio")
        let replay = root.appendingPathComponent("native-replay.wav")
        let replayResult: Result<Void, Error> = await withCheckedContinuation { c in recorder.saveReplay(url: replay) { c.resume(returning: $0) } }
        try replayResult.get()
        check(try AVAudioFile(forReading: replay).length > 48000, "Instant replay writes buffered audio to a valid WAV")
        check(NALoadClip(engine, 0, decoded, Int32(decoded.count / 2)) == 0, "Decoded recording loads into the native soundboard")
        NARoute(engine, 4, 0, 1); NAPlayClip(engine, 0, 0.5, 1, 0.01)
        try await Task.sleep(for: .seconds(1))
        check(NAMeter(engine, 6, 0) > 0.005 && NAClipPlaying(engine, 0) != 0, "Soundboard playback reaches the running mixer and live meter")
        NAStopClips(engine)
        try await Task.sleep(for: .milliseconds(200))
        check(NAClipPlaying(engine, 0) == 0, "Stop-all reaches the real audio callback")
        let presetURL = root.appendingPathComponent("roundtrip-preset.json")
        var session = Session(); session.channels[1].name = "Independent source"; session.channels[1].sends = [0,1,0,0.5]; session.effects[0].values[2] = 15; session.effects[0].order = [1,0,2,3,4,5,6]
        try SessionStore.save(session, to: presetURL); let loaded = try SessionStore.load(from: presetURL)
        check(loaded.channels[1].sends == session.channels[1].sends && loaded.effects[0].order == session.effects[0].order && loaded.effects[0].values[2] == 15, "Mixer routing and effect parameters survive a JSON save/load round trip")
        session.effects[0].order = [1,1,2,3,4,5,6]
        do { _ = try session.validated(); check(false, "Rejects malformed effect order") } catch { check(true, "Rejects malformed effect order") }
        NAStop(engine)
        let restart = NAStart(engine, [0,0,0,0,0], [0,0,0,0,0], [0,0,0,0], [0,0,0,0], AudioHardware.defaultOutput, Int32(originalBuffer))
        check(restart == 0, "Stops and restarts hardware callbacks cleanly")
        let duration = Int(ProcessInfo.processInfo.environment["NOIR_STABILITY_SECONDS"] ?? "15") ?? 15
        print("INFO Running silent hardware stability check for \(duration) seconds")
        for _ in 0..<duration { try await Task.sleep(for: .seconds(1)); NACollect(engine) }
        print("TELEMETRY CPU budget \(NALoad(engine))%, underruns \(NAUnderruns(engine)), dropped frames \(NAOverruns(engine))")
        check(NAUnderruns(engine) == 0 && NAOverruns(engine) == 0, "Silent physical-output run completes without underruns or dropped frames")
        NAStop(engine); recorder.shutdown(); NADestroy(engine)
        print("RESULT \(failures) native integration failures")
        exit(failures == 0 ? 0 : 1)
    }
}
