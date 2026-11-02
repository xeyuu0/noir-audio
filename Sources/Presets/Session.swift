// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct ChannelState: Codable, Identifiable {
    var id: Int
    var name: String
    var deviceUID = ""
    var pair = 0
    var gain: Float = 0
    var volume: Float = 1
    var balance: Float = 0
    var mute = false
    var solo = false
    var effects = false
    var sends: [Float] = [1, 0, 0, 0]
}
struct BusState: Codable, Identifiable {
    var id: Int
    var name: String
    var deviceUID = ""
    var pair = 0
    var volume: Float = 1
    var mute = false
}
struct EffectState: Codable {
    var values: [Float] = [0, 50, -1, 0, 100, 100, -1, 0.2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 20000, -18, 1, 0, 0, 1] + Array(repeating: 0, count: 9)
    var order: [Int32] = [0, 1, 2, 3, 4, 5, 6]
}
struct ClipState: Codable, Identifiable {
    var id: Int
    var name: String
    var path: String
    var volume: Float = 0.8
    var loop = false
    var fade: Float = 0.015
    var page: Int { id / 12 }
}
struct Session: Codable {
    var version = 1
    var name = "Clean Microphone"
    var channels: [ChannelState] = (0..<6).map { ChannelState(id: $0, name: ["Microphone", "Input 02", "Input 03", "Input 04", "Soundboard", "Application"][ $0 ]) }
    var buses: [BusState] = (0..<4).map { BusState(id: $0, name: ["Main", "Monitor", "Aux 2", "Aux 3"][$0]) }
    var effects = Array(repeating: EffectState(), count: 6)
    var bufferFrames = 256
    var clockUID = ""
    var clips: [ClipState] = []
    var replaySeconds = 30
    var recordSource = 0
    var recordingFolder = ""
    var setupComplete = false
    var menuBar = true
    var shortcuts: ShortcutPreferences?
    func validated() throws -> Session {
        try shortcuts?.validate()
        guard version == 1, channels.count == 6, buses.count == 4, effects.count == 6,
              channels.enumerated().allSatisfy({ $0.element.id == $0.offset && $0.element.sends.count == 4 && $0.element.pair >= 0 && $0.element.pair < 128 }),
              buses.enumerated().allSatisfy({ $0.element.id == $0.offset && $0.element.pair >= 0 && $0.element.pair < 128 }),
              effects.allSatisfy({ $0.values.count == 32 && Set($0.order) == Set(Int32(0)...Int32(6)) && $0.order.count == 7 && $0.values.allSatisfy(\.isFinite) }),
              clips.count <= 48, Set(clips.map(\.id)).count == clips.count, clips.allSatisfy({ (0..<48).contains($0.id) }),
              [64, 128, 256, 512, 1024].contains(bufferFrames), (5...120).contains(replaySeconds), (0...5).contains(recordSource)
        else { throw NoirError.message("The session file is invalid or uses an unsupported format.") }
        let ranges: [ClosedRange<Float>] = [0...5, 0...100, -1...41, -150...150, 60...150, 50...150, -1...14, 0...1, 0...1] + Array(repeating: -12...12, count: 7) + [0...500, 1000...20000, -48...0, 1...12, 0...18, 0...127, 0...1]
        guard effects.allSatisfy({ effect in ranges.enumerated().allSatisfy { $0.element.contains(effect.values[$0.offset]) } }),
              channels.allSatisfy({ (-60...24).contains($0.gain) && (0...2).contains($0.volume) && (-1...1).contains($0.balance) && $0.sends.allSatisfy { (0...1).contains($0) } }),
              buses.allSatisfy({ (0...2).contains($0.volume) }),
              clips.allSatisfy({ (0...2).contains($0.volume) && (0...2).contains($0.fade) })
        else { throw NoirError.message("The session contains out-of-range audio parameters.") }
        return self
    }
    static let presetNames = ["Clean Microphone", "Discord Voice", "Streaming", "Voice Effects", "Music Recording", "Soundboard + Microphone", "System Audio Recording"]
    mutating func applyPreset(_ name: String) {
        self.name = name
        for i in channels.indices { channels[i].mute = false; channels[i].solo = false; channels[i].effects = false; channels[i].gain = 0; channels[i].volume = 1; channels[i].sends = [0, 0, 0, 0] }
        effects = Array(repeating: EffectState(), count: 6)
        channels[0].sends[0] = 1
        switch name {
        case "Discord Voice", "Streaming":
            channels[0].effects = true; effects[0].values[0] = 5; effects[0].values[1] = 20
            effects[0].values[16] = 80; effects[0].values[19] = 3
        case "Voice Effects": channels[0].effects = true; effects[0].values[2] = 15
        case "Soundboard + Microphone": channels[4].sends[0] = 1
        case "System Audio Recording": channels[0].sends[0] = 0; channels[5].sends[0] = 1
        default: break
        }
    }
}

enum SessionStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NOIR Audio", isDirectory: true)
    }
    static var url: URL { directory.appendingPathComponent("Session.json") }
    static func save(_ session: Session, to target: URL = url) throws {
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(session).write(to: target, options: .atomic)
    }
    static func load(from target: URL = url) throws -> Session {
        try JSONDecoder().decode(Session.self, from: Data(contentsOf: target)).validated()
    }
}
