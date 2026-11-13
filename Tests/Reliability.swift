// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import AVFoundation
import CoreAudio

@main struct Reliability {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Build/Reliability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var failures = 0
        func check(_ condition: Bool, _ name: String) { print("\(condition ? "PASS" : "FAIL") \(name)"); if !condition { failures += 1 } }
        var samples = [Float](repeating: 0, count: 96000)
        for frame in 0..<48000 { let sample = Float(sin(Double(frame) * (2.0 * Double.pi * 440.0 / 48000.0)) * 0.1); samples[frame * 2] = sample; samples[frame * 2 + 1] = sample }
        let wav = root.appendingPathComponent("take.wav"), journals = root.appendingPathComponent("Recovery")
        var interrupted: RecoverableWAV? = try RecoverableWAV(destination: wav, journalDirectory: journals)
        // Malformed producer input must not crash or corrupt an otherwise valid take.
        for (input, count, label) in [
            ([Float](repeating: 0, count: 2), -1, "negative frames"),
            ([Float](repeating: 0, count: 2), 2, "insufficient stereo samples"),
            ([Float](repeating: 0, count: 2), Int.max, "overflowing frame count")
        ] {
            var rejected = false
            do { try interrupted!.write(input, frames: count) } catch { rejected = true }
            check(rejected, "WAV writer rejects \\(label) without trapping")
        }
        try interrupted!.write(samples, frames: 48000); interrupted = nil // Termination before finish/header update.
        let recovered = try RecoverableWAV.recover(in: journals)
        let file = try AVAudioFile(forReading: wav)
        check(recovered == [wav] && file.length == 48000 && file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == 24, "Interrupted take recovers every complete frame as a valid 24-bit WAV")
        let decoded = try ClipDecoder.decode(wav)
        check(zip(samples, decoded).allSatisfy { abs($0 - $1) < 0.000001 }, "Recovered PCM preserves reference samples to 24-bit precision")
        check(try RecoverableWAV.recover(in: journals).isEmpty, "Recovery is idempotent and clears completed journals")
        let m4a = root.appendingPathComponent("export.m4a")
        try AudioExport.aac(input: wav, destination: m4a)
        let compressed = try ClipDecoder.decode(m4a)
        check(abs(compressed.count - samples.count) < 4096 && (compressed.map(abs).max() ?? 0) > 0.07, "Native AAC export decodes with expected duration and signal amplitude")
        var session = Session(); session.setupComplete = true
        guard let output = AudioHardware.devices().first(where: { $0.id == AudioHardware.defaultOutput }) else { print("FAIL No hardware output for lifecycle tests"); exit(1) }
        session.clockUID = output.uid
        session.recordingFolder = root.path
        let settings = root.appendingPathComponent("Session.json"); try SessionStore.save(session, to: settings)
        let model = StudioModel(storageURL: settings)
        model.startAudio(); try await Task.sleep(for: .seconds(1))
        check(model.running, "Lifecycle test starts a silent physical clock with no microphone")
        model.startRecording(); model.stopAudio(); try await Task.sleep(for: .milliseconds(500))
        check(!model.recording && !model.recordingBusy, "Stopping audio during recording startup leaves no active writer or pending state")
        model.startAudio(); try await Task.sleep(for: .seconds(1))
        model.startRecording(); model.startRecording(); try await Task.sleep(for: .milliseconds(200))
        model.stopRecording(); try await Task.sleep(for: .milliseconds(200))
        check(!model.recording && !model.recordingBusy && model.lastRecording != nil, "Repeated record commands serialize into a single finalized take")
        model.importClips(urls: [wav]); model.importClips(urls: [wav])
        for _ in 0..<100 { if !model.loadingClips && model.session.clips.count == 2 { break }; try await Task.sleep(for: .milliseconds(50)) }
        check(model.session.clips.count == 2 && Set(model.session.clips.map(\.id)).count == 2, "Concurrent import requests reserve distinct soundboard slots")
        check(model.session.clips.allSatisfy { $0.path != wav.path && FileManager.default.fileExists(atPath: $0.path) }, "Imported clips are retained in the session's owned asset folder")
        let first = model.session.clips[0], ownedPath = first.path
        model.importClips(urls: [wav], replacing: first.id)
        for _ in 0..<100 { if !model.loadingClips { break }; try await Task.sleep(for: .milliseconds(50)) }
        check(model.session.clips.count == 2 && model.session.clips[0].path != ownedPath, "Replacement keeps the existing pad ID and saves new owned audio")
        model.removeClip(model.session.clips[0]); try await Task.sleep(for: .milliseconds(200))
        check(model.session.clips.count == 1 && FileManager.default.fileExists(atPath: wav.path), "Removing an imported pad preserves the user's original file")
        model.stopAudio(); model.session.channels[0].deviceUID = "missing-test-input"
        model.startAudio(); try await Task.sleep(for: .milliseconds(100))
        check(!model.running && !model.busy && model.error?.contains("unavailable") == true, "Unavailable persisted input fails explicitly before requesting microphone permission")
        model.stopAudio(); model.session.channels[0].deviceUID = ""; model.error = nil
        let aggregateUID = "audio.noir.validation.\(UUID().uuidString)"
        let properties: [String: Any] = [kAudioAggregateDeviceNameKey: "NOIR hot-plug validation", kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]], kAudioAggregateDeviceMainSubDeviceKey: output.uid]
        var aggregate: AudioObjectID = 0
        let created = AudioHardwareCreateAggregateDevice(properties as CFDictionary, &aggregate)
        if created == noErr {
            try await Task.sleep(for: .milliseconds(300)); model.refreshDevices(); model.session.clockUID = aggregateUID
            model.startAudio(); try await Task.sleep(for: .seconds(1))
            check(model.running, "A private test aggregate can clock the actual engine")
            _ = AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0
            try await Task.sleep(for: .milliseconds(300)); model.refreshDevices()
            check(!model.running, "Removal of a selected Core Audio device pauses routing")
            _ = AudioHardwareCreateAggregateDevice(properties as CFDictionary, &aggregate)
            try await Task.sleep(for: .milliseconds(500)); model.refreshDevices()
            check(model.running, "Returning the same device UID automatically restores routing")
            model.stopAudio(); if aggregate != 0 { _ = AudioHardwareDestroyAggregateDevice(aggregate) }
        } else { check(false, "Create a private aggregate for actual Core Audio device-removal validation (\(created))") }
        model.shutdown()
        print("RESULT \(failures) reliability failures"); exit(failures == 0 ? 0 : 1)
    }
}
