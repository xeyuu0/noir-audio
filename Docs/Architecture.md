# Architecture

## Control and rendering

`StudioModel` owns the session, device selections, engine lifetime and user actions on the main actor. A stable application delegate owns this model. Changes to live meters use a separate `EngineTelemetry` observable object: one snapshot per poll, published only when changed. Only views that display telemetry subscribe to it. This prevents the 30 Hz poll from recursively invalidating SwiftUI's scene and command-menu graph while setup is presented.

`NoirBridge.h` is the C boundary between Swift and `Engine.cpp`. Device selection and start/stop occur outside render callbacks. Each selected HAL device has an IOProc; a physical output clocks the mix even when headphone monitoring is silent. Independent inputs and secondary output clocks communicate through bounded stereo rings and adaptive resamplers. The internal mix uses 48 kHz Float32 samples in 128-frame blocks, independent of device callback sizes.

| Component | Responsibility |
| --- | --- |
| `Sources/AudioEngine` | HAL callbacks, source/bus controls, meters, soundboard scheduling, record/broadcast queues |
| `Sources/DSP` | Preallocated queues, windowed-sinc conversion, drift control, effects orchestration |
| `Sources/AudioDevices` | Device discovery and explicitly selected private process taps |
| `Sources/Recording` | Recoverable 24-bit WAV writing, rolling replay storage and native AAC export |
| `Sources/Broadcasting` | Independent encoder worker, protocol configuration, bounded SHOUTcast transport and retries |
| `Sources/Presets` | Validated Codable settings and atomic session persistence |
| `Sources/UI` | SwiftUI controls, monochrome meters, native glass/material surfaces |
| `Sources/VirtualDriver` | Bundled installer launch and exact-path driver removal |

The mixer has four hardware input strips, one soundboard strip and one process-tap strip. Each has four sends into Main, Monitor, Aux 2 and Aux 3. Each bus is stereo and can select one hardware channel pair. The 16-channel loopback exposes additional pairs, but this version is not a 16-bus mixer. Each output device can be assigned to only one bus. Combine sources with sends before the output rather than assigning one device to multiple buses.

## Real-time boundaries

Callback operations use preallocated storage and atomics. File decoding, filesystem access, network writes and SwiftUI updates occur outside callbacks. Effects are prepared on a serial worker, handed off atomically and crossfaded for 256 frames. Retired instances are reclaimed on the control side. The tests instrument heap allocation in DSP/mixer render sections; this does not claim to instrument Apple's audio service or every upstream driver operation.

Source gain, faders, sends and bus gain are smoothed. A stereo-linked safety limiter bounds bus peaks to 0.98. The diagnostics count limited frames, ring overflows and resampler underruns. CPU is the smoothed fraction of the master callback's time budget, not whole-process CPU. Latency is a software estimate; it does not include measured converter, acoustic or receiving-application delay.

Device lists are refreshed every two seconds. Missing selected devices pause active routing; reconnecting allows the model to retry it. That recovery logic exists but has not received a full physical hot-plug and Bluetooth test campaign.

## Effects

Original OctopusEAX headers provide the 15 room tables, 42 masks, VoiceShaper, VoiceFx, VoiceSpeed, spectral isolation, expander and seven-band EQ. The adapter adds native orchestration, filters and compression. Effect order and bypass are session data. Supported original algorithms are compared numerically against their upstream implementations.

Haunted Cavern uses the original narrow CardCore/loud-stage composition. Its separate wide headphone treatment and optional external measured convolution responses are not implemented. Speed and spectral processing can add substantial or variable delay; a low device buffer cannot remove DSP lookahead.

## Persistence and cleanup

The current session is atomically saved to `~/Library/Application Support/NOIR Audio/Session.json`. Mixer presets are JSON files with structural and parameter validation. Explicitly disconnected microphone input remains disconnected when a saved session is loaded. New soundboard imports are copied into the session's Clips directory. Replacement/removal deletes only owned copies, preserving the user's originals. Older sessions with external paths still load those paths. There are 48 slots, a five-minute per-clip limit and a 256 MB decoded-audio budget.

Shutdown invalidates the poll timer, waits for effect preparation, stops broadcasting and audio, drains worker teardown, destroys the process tap and releases the C++ engine. Recording data is handled on its own serial queue. Recording start/stop actions serialize, with generation tokens preventing repeated-start and stop-during-start races. RecoverableWAV writes a partial file plus an atomic journal, repairs the PCM header and synchronizes once per second, then finalizes on stop. Recovery derives complete frames from actual file length and never overwrites an existing take. The standard WAV limit is 4 GB. Missing storage and damaged journals can still require manual recovery. AAC export uses AVFoundation on a worker and writes a temporary file before replacement.

## Optional broadcasting

A selected bus feeds a bounded queue consumed by a background encoder worker. FFmpeg reads stereo float PCM on stdin. Icecast uses MP3, AAC or Opus; RTMP(S) uses AAC in FLV. SHOUTcast v1 uses a separate password/OK2 source handshake and forwards encoded MP3. Reconnection is bounded to eight retries. UI status distinguishes feeding an encoder from confirmation that a server or listener received audio.

Credentials are held in memory and raw encoder stderr is not displayed or logged. Encoder command-line arguments can contain server credentials and are visible to sufficiently privileged local process inspection. No remote server credentials are included in the project.

## Safe live updates and optional shortcuts

Decoded clips use an atomic ownership handoff. A serial preparation queue publishes pending clips; rendering adopts them at a block boundary and retires old storage into a bounded queue. Deletion happens outside rendering. Playback controls are separate from clip storage, so UI playing-state reads remain safe during replacement/removal. Concurrent import requests are serialized and reserve distinct slots.

Global hotkeys are opt-in Carbon registrations. Conflicts are reported explicitly and local menu shortcuts remain available. Handlers exist only while global shortcuts are enabled and are removed on shutdown. Shortcuts persist with validated session data; importing a mixer preset preserves local shortcuts and clips. Global combinations use physical US-layout positions.

Audio generation tokens cancel outstanding microphone-permission completions after Stop. Removing a real private Core Audio aggregate and recreating its UID passed automatic routing recovery; physical unplug, Bluetooth and sleep/wake remain unverified.

## Broadcast backpressure and TLS

EncoderInput uses nonblocking pipe writes, a two-second pending-PCM limit and a three-second progress timeout. Parent copies of child-only pipe ends are closed so termination produces EOF. UI telemetry updates are limited to four per second. SHOUTcast frames its OK2 response using bytes: CRLF is a single Swift Character, so searching the String for a lone LF does not work.

Secure Icecast uses FFmpeg's underlying HTTP PUT transport directly, since its Icecast wrapper drops TLS/CA options. Server certificate and hostname verification stay enabled; private servers may use an explicitly selected PEM authority. RTMPS passes those verification options to its TLS transport. Temporary test certificates are confined to ignored Build files.
