// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Foundation

// Compile the production exporter on CI without a logged-in audio session.
enum NoirError: Error { case message(String) }

@main
struct AACExportSmoke {
    static func main() throws {
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            print("PASS \(message)")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("noir-aac-ci-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var rejected = false
        do { try AudioExport.requireFrames(0) }
        catch { rejected = true }
        expect(rejected, "premature zero-frame read is rejected")
        try AudioExport.requireFrames(1)
        try AudioExport.requireFrames(4096)
        print("PASS nonempty encoder buffers are accepted")

        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let input = root.appendingPathComponent("input.wav")
        let writer = try AVAudioFile(forWriting: input, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        buffer.frameLength = 4096
        for channel in 0..<2 {
            for frame in 0..<4096 {
                buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 48000)) * 0.1
            }
        }
        try writer.write(from: buffer)
        let destination = root.appendingPathComponent("output.m4a")
        try AudioExport.aac(input: input, destination: destination)
        let exported = try AVAudioFile(forReading: destination)
        expect(exported.length > 0, "AAC export contains decodable audio")
        expect(FileManager.default.fileExists(atPath: destination.path), "AAC destination published on success")

        let sentinel = Data("keep-existing-export".utf8)
        let invalid = root.appendingPathComponent("invalid.wav")
        try Data("not a wave".utf8).write(to: invalid)
        try sentinel.write(to: destination)
        var failed = false
        do { try AudioExport.aac(input: invalid, destination: destination) }
        catch { failed = true }
        expect(failed, "invalid source fails export")
        let preserved = try Data(contentsOf: destination)
        expect(preserved == sentinel, "failed export preserves existing destination")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix(".noir-export-") }
        expect(leftovers.isEmpty, "temporary export files cleaned after failure")
        print("PASS standalone AAC export smoke tests")
    }
}
