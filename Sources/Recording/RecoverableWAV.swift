// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// Serial recorder queue only. A journal and periodically repaired PCM header let
// the next launch finish a take after process termination without losing its data.
final class RecoverableWAV {
    private struct Journal: Codable { let destination: URL; let partial: URL }
    private let destination: URL, partial: URL, journal: URL
    private var handle: FileHandle?
    private var dataBytes: UInt64 = 0
    private var lastSync = Date()
    init(destination: URL, journalDirectory: URL) throws {
        self.destination = destination
        partial = destination.deletingPathExtension().appendingPathExtension("partial.wav")
        journal = journalDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: destination.path), !FileManager.default.fileExists(atPath: partial.path) else { throw NoirError.message("A recording with this name already exists.") }
        try Self.header(bytes: 0).write(to: partial, options: .withoutOverwriting)
        do {
            try JSONEncoder().encode(Journal(destination: destination, partial: partial)).write(to: journal, options: .atomic)
            handle = try FileHandle(forUpdating: partial)
        } catch { try? FileManager.default.removeItem(at: partial); try? FileManager.default.removeItem(at: journal); throw error }
    }
    func write(_ samples: [Float], frames: Int) throws {
        guard let handle else { throw NoirError.message("The recording is already closed.") }
        // Reject malformed frame counts before multiplying or indexing the interleaved samples.
        // A short buffer must fail cleanly rather than trapping in the recorder worker.
        guard frames >= 0, frames <= samples.count / 2 else {
            throw NoirError.message("Recording input has an invalid frame count or insufficient stereo samples.")
        }
        guard frames <= (Int(UInt32.max) - 36) / 6 else {
            throw NoirError.message("The WAV reached its 4 GB size limit. Start a new take.")
        }
        let size = frames * 2 * 3
        guard dataBytes + UInt64(size) <= UInt64(UInt32.max) - 36 else {
            throw NoirError.message("The WAV reached its 4 GB size limit. Start a new take.")
        }
        var pcm = Data(count: size)
        pcm.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0..<(frames * 2) {
                let value = samples[i].isFinite ? max(-1, min(1, samples[i])) : 0
                let signed = Int32((Double(value) * 8388607).rounded())
                let bits = UInt32(bitPattern: signed)
                bytes[i * 3] = UInt8(truncatingIfNeeded: bits)
                bytes[i * 3 + 1] = UInt8(truncatingIfNeeded: bits >> 8)
                bytes[i * 3 + 2] = UInt8(truncatingIfNeeded: bits >> 16)
            }
        }
        try handle.seek(toOffset: 44 + dataBytes); try handle.write(contentsOf: pcm); dataBytes += UInt64(size)
        if Date().timeIntervalSince(lastSync) >= 1 { try updateHeader(); try handle.synchronize(); lastSync = Date() }
    }
    private func updateHeader() throws {
        guard let handle else { return }; try handle.seek(toOffset: 0); try handle.write(contentsOf: Self.header(bytes: UInt32(dataBytes)))
    }
    func finish() throws {
        guard let handle else { return }
        try updateHeader(); try handle.synchronize(); try handle.close(); self.handle = nil
        try FileManager.default.moveItem(at: partial, to: destination)
        try FileManager.default.removeItem(at: journal)
    }
    // Deliberately keep the journal on I/O failure. Recovery never overwrites a take.
    deinit { try? handle?.close() }
    static func recover(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        var recovered: [URL] = []
        for entry in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where entry.pathExtension == "json" {
            let record = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: entry))
            guard record.partial == record.destination.deletingPathExtension().appendingPathExtension("partial.wav") else { throw NoirError.message("An interrupted-recording journal has an invalid path.") }
            if !FileManager.default.fileExists(atPath: record.partial.path) {
                if FileManager.default.fileExists(atPath: record.destination.path) { try FileManager.default.removeItem(at: entry) }
                continue
            }
            let handle = try FileHandle(forUpdating: record.partial)
            do {
                let size = try handle.seekToEnd()
                guard size >= 44, size - 44 <= UInt32.max - 36 else { throw NoirError.message("An interrupted recording has an invalid size.") }
                let bytes = (size - 44) / 6 * 6
                try handle.truncate(atOffset: 44 + bytes); try handle.seek(toOffset: 0); try handle.write(contentsOf: header(bytes: UInt32(bytes))); try handle.synchronize(); try handle.close()
                var target = record.destination
                if FileManager.default.fileExists(atPath: target.path) { target = target.deletingPathExtension().appendingPathExtension("recovered-\(UUID().uuidString.prefix(8)).wav") }
                try FileManager.default.moveItem(at: record.partial, to: target); try FileManager.default.removeItem(at: entry); recovered.append(target)
            } catch { try? handle.close(); throw error }
        }
        return recovered
    }
    private static func header(bytes: UInt32) -> Data {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        text("RIFF"); number(bytes + 36); text("WAVEfmt "); number(UInt32(16)); number(UInt16(1)); number(UInt16(2))
        number(UInt32(48000)); number(UInt32(288000)); number(UInt16(6)); number(UInt16(24)); text("data"); number(bytes)
        return data
    }
}
