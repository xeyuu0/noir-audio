// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreAudio
import AppKit

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let inputs: Int
    let outputs: Int
    let rate: Double
    let buffer: UInt32
    var isVirtual: Bool { name.localizedCaseInsensitiveContains("BlackHole") || name.hasPrefix("NOIR ") }
}

enum AudioHardware {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func scalar<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, fallback: T) -> T {
        var a = address(selector), value = fallback, size = UInt32(MemoryLayout<T>.size)
        _ = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0) }
        return value
    }
    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var a = address(selector), value: CFString = "" as CFString, size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0) }
        return status == noErr ? value as String : ""
    }
    static func objects(_ selector: AudioObjectPropertySelector, from id: AudioObjectID = AudioObjectID(kAudioObjectSystemObject)) -> [AudioObjectID] {
        var a = address(selector), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
    static func channels(_ id: AudioDeviceID, input: Bool) -> Int {
        var a = address(kAudioDevicePropertyStreamConfiguration, input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let p = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { p.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, p) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(p.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
    static func devices() -> [AudioDevice] {
        objects(kAudioHardwarePropertyDevices).compactMap { id in
            guard scalar(id, kAudioDevicePropertyDeviceIsAlive, fallback: UInt32(0)) != 0 else { return nil }
            return AudioDevice(id: id, uid: string(id, kAudioDevicePropertyDeviceUID), name: string(id, kAudioObjectPropertyName), inputs: channels(id, input: true), outputs: channels(id, input: false), rate: scalar(id, kAudioDevicePropertyNominalSampleRate, fallback: 0.0), buffer: scalar(id, kAudioDevicePropertyBufferFrameSize, fallback: UInt32(0)))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static var defaultInput: AudioDeviceID { scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, fallback: AudioDeviceID(0)) }
    static var defaultOutput: AudioDeviceID { scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, fallback: AudioDeviceID(0)) }
}

struct AudioProcess: Identifiable, Hashable {
    let id: AudioObjectID
    let pid: pid_t
    let name: String
}

final class ApplicationTap {
    private(set) var tap: AudioObjectID = 0
    private(set) var aggregate: AudioDeviceID = 0
    static func processes() -> [AudioProcess] {
        AudioHardware.objects(kAudioHardwarePropertyProcessObjectList).compactMap { id in
            let pid = AudioHardware.scalar(id, kAudioProcessPropertyPID, fallback: pid_t(0))
            guard pid != ProcessInfo.processInfo.processIdentifier, let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { return nil }
            return AudioProcess(id: id, pid: pid, name: app.localizedName ?? app.bundleIdentifier ?? "Process \(pid)")
        }.sorted { $0.name < $1.name }
    }
    func create(process: AudioObjectID) throws {
        destroy()
        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.name = "NOIR selected application"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw NoirError.message("Application audio permission was denied or the process is unavailable (\(status)). Check System Settings → Privacy & Security → Screen & System Audio Recording.") }
        let uid = AudioHardware.string(tap, kAudioTapPropertyUID)
        let properties: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NOIR Private Capture",
            kAudioAggregateDeviceUIDKey: "audio.noir.capture.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: uid, kAudioSubTapDriftCompensationKey: true]]
        ]
        status = AudioHardwareCreateAggregateDevice(properties as CFDictionary, &aggregate)
        guard status == noErr else { destroy(); throw NoirError.message("Could not create the private application input (\(status)).") }
    }
    func destroy() { if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }; if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 } }
    deinit { destroy() }
}

enum NoirError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let text) = self { return text }; return nil } }
