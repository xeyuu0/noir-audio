// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// Compile the production writer in isolation so GitHub Actions can verify
// recorder invariants without a logged-in Core Audio device or app session.
enum NoirError: Error { case message(String) }

@main
struct RecoverableWAVSmoke {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("noir-wav-ci-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            print("PASS \(message)")
        }
        func rejects(_ writer: RecoverableWAV, _ samples: [Float], frames: Int) -> Bool {
            do { try writer.write(samples, frames: frames); return false }
            catch { return true }
        }

        let journals = root.appendingPathComponent("journals")
        let output = root.appendingPathComponent("take.wav")
        let writer = try RecoverableWAV(destination: output, journalDirectory: journals)
        expect(rejects(writer, [0, 0], frames: -1), "negative frames rejected")
        expect(rejects(writer, [0, 0], frames: 2), "undersized stereo buffer rejected")
        expect(rejects(writer, [0, 0], frames: Int.max), "overflowing frame count rejected")
        try writer.write([0.5, -0.5, 0, 0], frames: 2)
        try writer.finish()
        let bytes = try Data(contentsOf: output)
        expect(bytes.count == 44 + 12, "valid stereo frames remain writable")
        expect(String(data: bytes.prefix(4), encoding: .ascii) == "RIFF", "RIFF header retained")
        expect(String(data: bytes[8..<12], encoding: .ascii) == "WAVE", "WAVE header retained")
        let completedRecovery = try RecoverableWAV.recover(in: journals)
        expect(completedRecovery.isEmpty, "completed take has no recovery journal")

        let interruptedURL = root.appendingPathComponent("interrupted.wav")
        var interrupted: RecoverableWAV? = try RecoverableWAV(destination: interruptedURL, journalDirectory: journals)
        try interrupted!.write([0.25, -0.25], frames: 1)
        interrupted = nil
        let recovered = try RecoverableWAV.recover(in: journals)
        expect(recovered == [interruptedURL], "interrupted take recovered")
        let recoveredBytes = try Data(contentsOf: interruptedURL)
        expect(recoveredBytes.count == 50, "recovered take retains complete stereo frame")

        // Verify PCM conversion at the boundaries and for non-finite input.
        let pcmURL = root.appendingPathComponent("pcm-integrity.wav")
        let pcm = try RecoverableWAV(destination: pcmURL, journalDirectory: journals)
        try pcm.write([2, -2, .nan, .infinity, -.infinity, 0], frames: 3)
        try pcm.finish()
        let pcmBytes = try Data(contentsOf: pcmURL)
        expect(pcmBytes.count == 62, "three stereo frames produce exactly 18 PCM bytes")
        expect(Array(pcmBytes[44..<62]) == [
            0xff, 0xff, 0x7f, 0x01, 0x00, 0x80,
            0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0
        ], "clipping and non-finite samples have deterministic 24-bit encoding")
        func little32(_ offset: Int) -> UInt32 {
            UInt32(pcmBytes[offset]) | UInt32(pcmBytes[offset + 1]) << 8 |
            UInt32(pcmBytes[offset + 2]) << 16 | UInt32(pcmBytes[offset + 3]) << 24
        }
        expect(little32(4) == 54 && little32(40) == 18, "RIFF and data lengths match PCM payload")

        // An interrupted take may contain a torn final stereo frame. Recovery must
        // discard only the incomplete tail and preserve the complete frames.
        let tornURL = root.appendingPathComponent("torn.wav")
        var torn: RecoverableWAV? = try RecoverableWAV(destination: tornURL, journalDirectory: journals)
        try torn!.write([0.25, -0.25], frames: 1)
        torn = nil
        let tornPartial = tornURL.deletingPathExtension().appendingPathExtension("partial.wav")
        let tailHandle = try FileHandle(forWritingTo: tornPartial)
        try tailHandle.seekToEnd()
        try tailHandle.write(contentsOf: Data([0x12, 0x34, 0x56]))
        try tailHandle.close()
        let tornRecovered = try RecoverableWAV.recover(in: journals)
        expect(tornRecovered == [tornURL], "torn recording is recovered")
        let tornBytes = try Data(contentsOf: tornURL)
        expect(tornBytes.count == 50, "partial stereo frame is truncated")

        // A destination created after the recording starts must never be replaced.
        let collisionURL = root.appendingPathComponent("collision.wav")
        var collision: RecoverableWAV? = try RecoverableWAV(destination: collisionURL, journalDirectory: journals)
        try collision!.write([0.1, -0.1], frames: 1)
        collision = nil
        let sentinel = Data("keep-existing-take".utf8)
        try sentinel.write(to: collisionURL)
        let collisionRecovered = try RecoverableWAV.recover(in: journals)
        expect(collisionRecovered.count == 1 && collisionRecovered[0] != collisionURL, "recovery chooses a new name on collision")
        let collisionBytes = try Data(contentsOf: collisionURL)
        expect(collisionBytes == sentinel, "recovery preserves existing destination bytes")
        let renamedBytes = try Data(contentsOf: collisionRecovered[0])
        expect(renamedBytes.count == 50, "renamed recovered take is intact")

        print("PASS standalone RecoverableWAV smoke tests")
    }
}
