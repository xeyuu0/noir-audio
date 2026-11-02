// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import AVFoundation

// All file writes, replay storage, and AVFoundation calls run away from HAL callbacks.
final class Recorder {
    private let queue = DispatchQueue(label: "audio.noir.recorder", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var file: RecoverableWAV?
    private let journalDirectory: URL
    private var replay = [Float](repeating: 0, count: 48000 * 2 * 30)
    private var head = 0, valid = 0
    private var scratch = [Float](repeating: 0, count: 8192)
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true)!
    private let buffer: AVAudioPCMBuffer
    var onError: ((String) -> Void)?
    private var engine: NAEngine
    init(engine: NAEngine, journalDirectory: URL = SessionStore.directory.appendingPathComponent("Recording Recovery")) {
        self.engine = engine; self.journalDirectory = journalDirectory; buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.drain() }; self.timer = timer; timer.resume()
    }
    private func drain() {
        while true {
            let n = Int(NAReadRecord(engine, &scratch, 4096)); if n == 0 { break }
            for i in 0..<(n * 2) { replay[head] = scratch[i]; head = (head + 1) % replay.count; valid = min(valid + 1, replay.count) }
            if let file {
                do { try file.write(scratch, frames: n) } catch { self.file = nil; onError?("Recording stopped: \(error.localizedDescription). Any unfinished take will be recovered on the next launch.") }
            }
        }
    }
    private static var settings: [String: Any] {
        [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    }
    func start(url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            do {
                guard file == nil else { throw NoirError.message("A recording is already active.") }
                drain() // Previously queued audio belongs to replay, not the new take.
                file = try RecoverableWAV(destination: url, journalDirectory: journalDirectory); completion(.success(()))
            }
            catch { completion(.failure(error)) }
        }
    }
    func stop(completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
        queue.async {
            self.drain()
            do { try self.file?.finish(); self.file = nil; completion(.success(())) }
            catch { self.file = nil; completion(.failure(error)) }
        }
    }
    func recover(completion: @escaping (Result<[URL], Error>) -> Void) {
        queue.async { completion(Result { try RecoverableWAV.recover(in: self.journalDirectory) }) }
    }
    func setReplay(seconds: Int) { queue.async { self.replay = [Float](repeating: 0, count: 48000 * 2 * max(5, min(120, seconds))); self.head = 0; self.valid = 0 } }
    func clearReplay() { queue.async { self.head = 0; self.valid = 0 } }
    func saveReplay(url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            do {
                guard valid > 0 else { throw NoirError.message("Start audio first to fill the replay buffer.") }
                let out = try AVAudioFile(forWriting: url, settings: Self.settings, commonFormat: .pcmFormatFloat32, interleaved: true)
                var offset = 0; let start = (head - valid + replay.count) % replay.count
                while offset < valid {
                    let count = min(8192, valid - offset)
                    for i in 0..<count { scratch[i] = replay[(start + offset + i) % replay.count] }
                    buffer.frameLength = AVAudioFrameCount(count / 2)
                    _ = scratch.withUnsafeBytes { memcpy(buffer.audioBufferList.pointee.mBuffers.mData!, $0.baseAddress!, count * 4) }
                    try out.write(from: buffer); offset += count
                }
                completion(.success(()))
            } catch { completion(.failure(error)) }
        }
    }
    func shutdown() { timer?.cancel(); timer = nil; queue.sync { drain(); try? file?.finish(); file = nil } }
}
