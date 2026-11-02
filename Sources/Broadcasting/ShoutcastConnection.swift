// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Network

// SHOUTcast v1 source login is password + OK2 + icy headers, not Icecast's HTTP SOURCE.
// Bounded writes apply backpressure only to the encoder worker, never to an audio callback.
final class ShoutcastConnection: @unchecked Sendable {
    private let queue = DispatchQueue(label: "audio.noir.shoutcast.network")
    private let connection: NWConnection
    private let password: String
    private let headers: Data
    private var completed = false
    private var response = Data()
    init(configuration: BroadcastConfiguration) throws {
        guard let url = URLComponents(string: configuration.endpoint), let host = url.host, let port = NWEndpoint.Port(rawValue: UInt16(exactly: url.port ?? 8001) ?? 0), port.rawValue != 0,
              !configuration.password.utf8.contains(10), !configuration.password.utf8.contains(13),
              !configuration.title.utf8.contains(10), !configuration.title.utf8.contains(13) else { throw NoirError.message("Enter a valid SHOUTcast source port, password, and single-line title.") }
        connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        password = configuration.password
        let title = configuration.title.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        headers = Data("icy-name:\(title)\r\nicy-pub:0\r\nicy-br:\(configuration.bitrate)\r\ncontent-type:audio/mpeg\r\n\r\n".utf8)
    }
    func connect(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.connection.send(content: Data((self.password + "\r\n").utf8), completion: .contentProcessed { error in
                    if let error { self.finish(.failure(error), completion) } else { self.readLogin(completion) }
                })
            case .failed(let error): self.finish(.failure(error), completion)
            case .cancelled: self.finish(.failure(NoirError.message("Connection cancelled.")), completion)
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 8) { [weak self] in self?.finish(.failure(NoirError.message("SHOUTcast login timed out.")), completion) }
    }
    private func finish(_ result: Result<Void, Error>, _ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        guard !completed else { return }; completed = true; completion(result)
        if case .failure = result { connection.cancel() }
    }
    private func readLogin(_ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, ended, error in
            guard let self else { return }
            if let error { self.finish(.failure(error), completion); return }
            if let data { self.response.append(data) }
            // CRLF is one Swift Character; searching the String for a lone LF
            // does not find it. Frame this wire protocol using bytes.
            if let newline = self.response.firstIndex(of: 10) {
                var line = self.response[..<newline]
                if line.last == 13 { line = line.dropLast() }
                guard line.elementsEqual("OK2".utf8) else { self.finish(.failure(NoirError.message("SHOUTcast rejected the source password.")), completion); return }
                self.connection.send(content: self.headers, completion: .contentProcessed { error in self.finish(error.map { .failure($0) } ?? .success(()), completion) })
            } else if ended || self.response.count > 4096 { self.finish(.failure(NoirError.message("Invalid SHOUTcast login response.")), completion) }
            else { self.readLogin(completion) }
        }
    }
    func write(_ data: Data) throws {
        let done = DispatchSemaphore(value: 0)
        let result = SendResult()
        connection.send(content: data, completion: .contentProcessed { error in result.error = error; done.signal() })
        guard done.wait(timeout: .now() + 5) == .success else { connection.cancel(); throw NoirError.message("SHOUTcast send timed out.") }
        if let error = result.error { throw error }
    }
    func cancel() { connection.cancel() }
    private final class SendResult: @unchecked Sendable { var error: Error? }
}
