// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation

enum AudioExport {
    // Native encoder on a worker queue; export never touches the render callback.
    static func aac(input: URL, destination: URL) throws {
        guard input.standardizedFileURL != destination.standardizedFileURL else { throw NoirError.message("Choose a separate export file.") }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".noir-export-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            let source = try AVAudioFile(forReading: input, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 4096) else { throw NoirError.message("Could not prepare the export buffer.") }
            let output = try AVAudioFile(forWriting: temporary, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: source.processingFormat.sampleRate, AVNumberOfChannelsKey: source.processingFormat.channelCount, AVEncoderBitRateKey: 192000], commonFormat: .pcmFormatFloat32, interleaved: false)
            while source.framePosition < source.length { try source.read(into: buffer); if buffer.frameLength == 0 { break }; try output.write(from: buffer) }
        } // Close the encoder and finish its container before moving it.
        if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: destination) }
    }
}
