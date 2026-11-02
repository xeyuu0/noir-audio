// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main struct BroadcastIntegration {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 5 else { exit(2) }
        let mode = args[1], endpoint = args[2], codec = args[3], duration = Int(args[4]) ?? 8
        let engine = NACreate()!, model = BroadcastModel()
        defer { model.shutdown(); NAStop(engine); NADestroy(engine) }
        var tone = [Float](repeating: 0, count: 48000 * 2)
        for i in 0..<48000 { let value = Float(sin(Double(i) * 2 * Double.pi * 440 / 48000) * 0.1); tone[i*2] = value; tone[i*2+1] = value }
        _ = NALoadClip(engine, 0, tone, 48000); NAPlayClip(engine, 0, 1, 1, 0); NARoute(engine, 4, 3, 1)
        guard NAStart(engine, [0,0,0,0,0], [0,0,0,0,0], [0,0,0,0], [0,0,0,0], AudioHardware.defaultOutput, 256) == 0 else {
            print("FAIL \(String(cString: NAError(engine)))"); exit(1)
        }
        model.config.kind = endpoint.hasPrefix("shoutcast") ? .shoutcast : endpoint.hasPrefix("rtmp") ? .rtmp : .icecast
        model.config.codec = codec == "aac" ? .aac : codec == "opus" ? .opus : .mp3
        model.config.endpoint = endpoint; model.config.password = mode == "bad-auth" ? "wrong-test-password" : "noir-test-password"
        model.config.reconnect = mode == "reconnect"
        model.config.title = "NOIR Local Validation"
        model.config.certificateAuthority = ProcessInfo.processInfo.environment["NOIR_TEST_CA"] ?? ""
        if let executable = ProcessInfo.processInfo.environment["NOIR_TEST_ENCODER"] { model.config.executable = executable }
        model.start(engine: engine)
        var scratch = [Float](repeating: 0, count: 8192), heartbeats = 0
        let deadline = Date().addingTimeInterval(Double(duration))
        while Date() < deadline {
            while NAReadRecord(engine, &scratch, 4096) > 0 {}
            NACollect(engine); heartbeats += 1
            try await Task.sleep(for: .milliseconds(20))
        }
        let active = model.active, bytes = model.bytes, status = model.status
        print("STATE \(mode): \(status); PCM bytes \(bytes)")
        let stopping = Date(); model.shutdown(); let stopTime = Date().timeIntervalSince(stopping)
        var failed = 0
        func check(_ pass: Bool, _ name: String) { print("\(pass ? "PASS" : "FAIL") \(name)"); if !pass { failed += 1 } }
        if ["bad-auth", "untrusted-tls", "wrong-hostname", "stalled"].contains(mode) { check(!active, "\(mode): failed connection exits encoder activity") }
        else { check(active && bytes > 100000, "\(mode)/\(codec): real callback audio reaches encoder stdin") }
        check(stopTime < 3, "\(mode): disconnect and worker teardown complete within three seconds (\(String(format: "%.3f", stopTime))s)")
        check(heartbeats > duration * 30, "\(mode): main actor stays responsive while encoding")
        check(!status.contains("noir-test-password") && !status.contains("wrong-test-password"), "\(mode): UI diagnostics do not expose source credentials")
        print("RESULT \(failed) broadcast-client failures"); exit(failed == 0 ? 0 : 1)
    }
}
