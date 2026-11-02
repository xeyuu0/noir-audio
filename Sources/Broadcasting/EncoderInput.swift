// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

// Owned by the broadcast worker. A stalled encoder can never block UI teardown
// or hold a callback queue indefinitely. The maximum pending PCM is two seconds.
final class EncoderInput {
    private let handle: FileHandle
    private var pending = Data()
    private var offset = 0
    private var lastProgress = Date()
    private var closed = false
    init(_ handle: FileHandle) throws {
        self.handle = handle
        let flags = fcntl(handle.fileDescriptor, F_GETFL)
        guard flags >= 0, fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { throw NoirError.message("Could not prepare the encoder input pipe.") }
    }
    func append(_ data: Data) throws -> Int {
        guard !closed else { throw NoirError.message("Encoder input closed.") }
        if offset > 0 { pending.removeFirst(offset); offset = 0 }
        guard pending.count + data.count <= 48000 * 8 * 2 else { throw NoirError.message("The encoder stopped consuming audio.") }
        pending.append(data)
        let written = try pending.withUnsafeBytes { bytes -> Int in
            guard !bytes.isEmpty else { return 0 }
            let count = Darwin.write(handle.fileDescriptor, bytes.baseAddress!, bytes.count)
            if count >= 0 { return count }
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return 0 }
            throw NoirError.message("The encoder input closed unexpectedly.")
        }
        offset = written
        if written > 0 || pending.isEmpty { lastProgress = Date() }
        else if Date().timeIntervalSince(lastProgress) > 3 { throw NoirError.message("The encoder input timed out.") }
        return written
    }
    func close() { guard !closed else { return }; closed = true; try? handle.close(); pending.removeAll() }
    deinit { close() }
}
