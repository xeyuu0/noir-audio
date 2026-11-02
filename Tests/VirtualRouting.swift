// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreAudio

@main struct VirtualRouting {
    static func main() throws {
        let devices = AudioHardware.devices()
        guard let loop = devices.first(where: { $0.name == "NOIR Loopback" }), loop.inputs == 16, loop.outputs == 16,
              let clock = devices.first(where: { $0.id == AudioHardware.defaultOutput && !$0.isVirtual }) else {
            print("FAIL Installed 16-channel NOIR Loopback and a physical default output are required"); exit(1)
        }
        var failures = 0
        func check(_ condition: Bool, _ text: String) { print("\(condition ? "PASS" : "FAIL") \(text)"); if !condition { failures += 1 } }
        let engine = NACreate()!
        defer { NAStop(engine); NADestroy(engine) }
        // Use only the last loopback pair. No microphone is captured and the
        // physical clock output receives silence. Main never receives its return.
        var source = [Float](repeating: 0, count: 48000 * 2)
        var sequence = [Float](repeating: 0, count: 1024)
        var seed: UInt32 = 0x12345678
        for i in sequence.indices { seed = seed &* 1664525 &+ 1013904223; sequence[i] = seed & 1 == 0 ? 0.08 : -0.08; seed ^= seed >> 11 }
        for i in sequence.indices { source[(4800 + i) * 2] = sequence[i]; source[(4800 + i + 512) * 2 + 1] = sequence[i] * 0.5 }
        _ = NALoadClip(engine, 0, source, 48000); NAPlayClip(engine, 0, 1, 0, 0)
        NARoute(engine, 4, 0, 1); NARecordSource(engine, 4)
        let status = NAStart(engine, [loop.id,0,0,0,0], [7,0,0,0,0], [loop.id,0,0,0], [7,0,0,0], clock.id, Int32(clock.buffer))
        check(status == 0, "Installed loopback opens for simultaneous output and input on channels 15–16")
        guard status == 0 else { print(String(cString: NAError(engine))); exit(1) }
        var captured: [Float] = [], scratch = [Float](repeating: 0, count: 8192)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let frames = Int(NAReadRecord(engine, &scratch, 4096)); captured.append(contentsOf: scratch.prefix(frames * 2))
            NACollect(engine); Thread.sleep(forTimeInterval: 0.005)
        }
        func match(channel: Int) -> (Int, Double) {
            var best = (0, -Double.infinity)
            for offset in 4800..<min(24000, captured.count / 2 - sequence.count) {
                var sum = 0.0
                for i in sequence.indices { sum += Double(sequence[i] * captured[(offset+i)*2+channel]) }
                if sum > best.1 { best = (offset, sum) }
            }
            return best
        }
        guard captured.count > 48000 * 2 else { print("FAIL No timed return audio"); exit(1) }
        let left = match(channel: 0), right = match(channel: 1)
        check(left.1 > 1 && right.1 > 0.4, "Known signal returns through the installed HAL driver")
        check(abs((right.0-left.0)-512) <= 2, "Separate left/right signals preserve channel order and relative timing")
        let delay = Double(left.0 - 4800) / 48
        print("MEASUREMENT Installed loopback + NOIR output/input converters: \(String(format: "%.2f", delay)) ms at driver \(loop.rate) Hz and clock \(clock.rate) Hz")
        check(delay > 0 && delay < 300, "Measured digital round-trip delay is bounded")
        check(NAOverruns(engine) == 0, "Loopback recording queue has no dropped frames")
        let duration = Int(ProcessInfo.processInfo.environment["NOIR_STABILITY_SECONDS"] ?? "0") ?? 0
        if duration > 0 {
            let initialUnderruns = NAUnderruns(engine), initialDrops = NAOverruns(engine)
            NAPlayClip(engine, 0, 1, 1, 0)
            print("INFO Starting \(duration)-second installed loopback stability run"); fflush(stdout)
            let stop = Date().addingTimeInterval(Double(duration))
            var audible = 0, frames = 0
            while Date() < stop {
                let n = Int(NAReadRecord(engine, &scratch, 4096)); frames += n
                audible += scratch.prefix(n * 2).filter { abs($0) > 0.01 }.count
                NACollect(engine); Thread.sleep(forTimeInterval: 0.005)
            }
            print("TELEMETRY \(duration)s, \(frames) received frames, CPU budget \(NALoad(engine))%, new underruns \(NAUnderruns(engine)-initialUnderruns), new dropped frames \(NAOverruns(engine)-initialDrops)")
            check(audible > duration * 500, "Repeated test signal continues through installed loopback throughout the stability run")
            check(NAUnderruns(engine) == initialUnderruns && NAOverruns(engine) == initialDrops, "Extended installed-driver run has no additional underruns or dropped frames")
        }
        NAStop(engine)
        print("RESULT \(failures) installed virtual-routing failures")
        exit(failures == 0 ? 0 : 1)
    }
}
