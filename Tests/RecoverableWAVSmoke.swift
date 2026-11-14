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
        expect(try RecoverableWAV.recover(in: journals).isEmpty, "completed take has no recovery journal")

        let interruptedURL = root.appendingPathComponent("interrupted.wav")
        var interrupted: RecoverableWAV? = try RecoverableWAV(destination: interruptedURL, journalDirectory: journals)
        try interrupted!.write([0.25, -0.25], frames: 1)
        interrupted = nil
        let recovered = try RecoverableWAV.recover(in: journals)
        expect(recovered == [interruptedURL], "interrupted take recovered")
        expect((try Data(contentsOf: interruptedURL)).count == 50, "recovered take retains complete stereo frame")
        print("PASS standalone RecoverableWAV smoke tests")
    }
}
