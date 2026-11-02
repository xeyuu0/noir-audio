// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import AudioToolbox

enum ClipDecoder {
    static func decode(_ url: URL) throws -> [Float] {
        var file: ExtAudioFileRef?
        let opened = ExtAudioFileOpenURL(url as CFURL, &file)
        guard opened == noErr, let file else { throw NoirError.message("macOS cannot decode \(url.lastPathComponent) (\(opened)).") }
        defer { ExtAudioFileDispose(file) }
        var source = AudioStreamBasicDescription(), size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &source)
        var length: Int64 = 0; size = UInt32(MemoryLayout<Int64>.size)
        ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &size, &length)
        guard source.mSampleRate > 0, Double(length) / source.mSampleRate <= 300 else { throw NoirError.message("Soundboard clips can be up to five minutes long.") }
        var format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let status = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: format)), &format)
        guard status == noErr else { throw NoirError.message("Could not convert this clip to 48 kHz stereo (\(status)).") }
        var result: [Float] = []; result.reserveCapacity(Int(Double(length) * 48000 / source.mSampleRate + 1024) * 2)
        var chunk = [Float](repeating: 0, count: 8192)
        while true {
            var frames: UInt32 = 4096
            let read = chunk.withUnsafeMutableBytes { bytes -> OSStatus in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
                return ExtAudioFileRead(file, &frames, &list)
            }
            guard read == noErr else { throw NoirError.message("Audio decoding failed (\(read)).") }
            if frames == 0 { break }; result.append(contentsOf: chunk.prefix(Int(frames) * 2))
        }
        return result
    }
}
