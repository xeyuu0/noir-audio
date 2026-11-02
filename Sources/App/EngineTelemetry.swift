// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

struct EngineSnapshot: Equatable {
    var peaks = Array(repeating: Float(0), count: 10)
    var rms = Array(repeating: Float(0), count: 10)
    var waveform = Array(repeating: Float(0), count: 256)
    var cpu: Double = 0
    var latency: Double = 0
    var underruns: UInt64 = 0
    var overruns: UInt64 = 0
    var clipped: UInt64 = 0
}

// Meter invalidations belong to the content view, never to SwiftUI's scene/menu graph.
@MainActor final class EngineTelemetry: ObservableObject {
    @Published private(set) var snapshot = EngineSnapshot()
    func poll(engine: NAEngine, running: Bool) {
        var next = snapshot
        for i in 0..<10 { next.peaks[i] = NAMeter(engine, Int32(i), 0); next.rms[i] = NAMeter(engine, Int32(i), 1) }
        var points = [Float](repeating: 0, count: 2048)
        let n = Int(NAWaveform(engine, &points, 2048))
        if n > 0 { next.waveform = Array((next.waveform + points.prefix(n)).suffix(256)) }
        next.cpu = running ? NALoad(engine) : 0
        next.latency = NALatency(engine)
        next.underruns = NAUnderruns(engine); next.overruns = NAOverruns(engine); next.clipped = NAClips(engine)
        if next != snapshot { snapshot = next }
    }
}
