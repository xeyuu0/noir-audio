# Validation and release status

NOIR Audio 0.1.0 is an Apple Silicon development preview. These are observed results, with receiving-application and platform checks listed separately.

Host: arm64, macOS 27.2 (26B123), Xcode 27.1 (27A9275), Swift 6.4 in Swift 5 language mode. Final software checks were run on 2 November 2026.

## Recorded evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Release app / ad-hoc signature | Build and strict verification passed | `Build/app-build.log`, `Scripts/build.sh` |
| DSP, mixer, resampling, clip ownership | 28 passed | `Tests/Results/core-tests.log` |
| Address / undefined-behavior sanitizers | Same 28 passed without reports | `Tests/Results/sanitizer-tests.log` |
| Native Core Audio integration | 13 passed | `Tests/Results/native-integration.log` |
| Recording, assets, device recovery | 15 passed | `Tests/Results/reliability-tests.log` |
| BlackHole driver harness | 14 passed across 2 and 16 channels | `Tests/Results/driver-tests.log` |
| Launch-state regression | 7 passed | `Tests/Results/launch-state-tests.log` |
| Packaged UI | 8 assertions across three launches | `Tests/Results/ui-launch-tests.log` |
| Custom/global shortcuts | 10 passed | `Tests/Results/shortcut-tests.log` |
| Broadcast configuration | 8 passed | `Tests/Results/broadcast-configuration-tests.log` |
| Actual broadcast receivers and failures | 33 server checks + 56 client checks passed | `Tests/Results/broadcast-tests.log` |
| Installed virtual driver | 7 passed, including completed 30-minute installed-driver stability run | `Tests/Results/virtual-routing-tests.log` |

## DSP and callback behavior

Tests compare 14 stereo room impulses, the original narrow Haunted Cavern composition, all 42 masks and isolation modes against upstream behavior. They exercise EQ, mismatched-rate pitch preservation, simulated clock drift, independent buses, mute/solo/balance, limiting, soundboard loop/stop, live replacement/removal and concurrent effect/clip handoff. Instrumented DSP/mixer rendering made no heap allocations. This does not instrument Apple's audio services or every upstream HAL operation.

## Native recording and reliability

Real physical-output callbacks clocked the engine with silent hardware output. An internally routed 440 Hz tone was recorded to a valid stereo 48 kHz 24-bit WAV, decoded and played through the soundboard. Replay, preset persistence and stop/restart passed. The final 15-second native run recorded zero underruns/dropped frames and approximately 2.83% smoothed callback budget.

The reliability suite recovers an interrupted WAV from its complete PCM frames, checks sample precision and idempotence, then exports and decodes AAC. It verifies stop-during-record-start, duplicate recording requests, concurrent imports, owned asset copies, replacement/removal and preservation of originals. Removing a real private Core Audio aggregate pauses active routing; recreating the same UID restores it. This is not a physical cable/Bluetooth unplug test.

## Launch and shortcuts

The reported stack-guard fault came from repeated SwiftUI scene/command processing. The delegate now owns a stable model, telemetry is separately observable, unchanged snapshots do not republish, and setup is deferred until a window appears. The model test records zero scene-model publications while actual HAL callbacks and telemetry run. The packaged UI test visits all nine sections, opens/dismisses setup, quits normally and relaunches three times, leaving Dashboard open with audio stopped.

Shortcut tests verify opt-in global behavior, persistence, legacy session decoding, malformed/duplicate rejection, actual OS registration/conflicts, native event dispatch, disabling and shutdown cleanup. Global combinations use physical US-layout positions; non-US keyboard mapping requires manual checking.

## Broadcasting

Isolated local Icecast servers and separate FFmpeg listeners received MP3, AAC and Opus as 48 kHz stereo with the expected 440 Hz signal and amplitude. SHOUTcast v1 uses Icecast's compatibility listener. RTMP reaches an FFmpeg receiver; RTMPS uses a local TLS proxy in front of it because FFmpeg has no RTMPS listening mode.

Tests verify bad credentials, untrusted certificates, a trusted certificate for the wrong hostname, delayed server startup, termination/restart of an established server, and an encoder that stops reading. Main-actor heartbeat and teardown checks pass. Production code keeps TLS verification enabled. Local test authorities are supplied explicitly. Raw encoder stderr and source credentials never reach UI diagnostics. No public servers or live broadcasts were used.

## Virtual devices and measured latency

Both NOIR driver bundles are installed and exposed by Core Audio. The installed test uses loopback channels 15–16 with a silent physical clock and an asymmetric stereo sequence, verifying real transport, channel order and correlation. The observed digital round trip was 76.71 ms with the virtual device at 48 kHz and the physical clock at 44.1 kHz. This includes NOIR's buffers and conversion; it is not acoustic microphone-to-headphone latency.

The final installed-loopback stability run completed 1,800 seconds (30 minutes): 86,401,664 received frames, 3.54% reported callback CPU budget, zero additional underruns, and zero additional dropped frames. Its signal, channel-order, and digital round-trip checks also passed. Earlier two-hour attempts were interrupted and are not counted as successful tests.

## Still unverified

- Physical microphone capture/listening, denied microphone permission, and DSP listening quality on the intended interface.
- NOIR Microphone reception in Discord, Zoom, OBS or Logic Pro, with simultaneous headphone monitoring. No generated test signal was sent to NOIR Microphone during automated validation.
- Selected process-tap capture, permission transitions, multi-process apps and protected content.
- Physical unplug/reconnect, Bluetooth format changes, sleep/wake, and clean-machine installer upgrade/repair/removal.
- Earlier supported macOS versions, Intel builds, public internet streaming services and acoustic cable-loopback latency.
- Developer ID signing, notarization and clean-machine Gatekeeper checks. The keychain reports zero available signing identities. The app is ad-hoc signed, the installer is unsigned, and neither is notarized.

## Feature boundaries

- Four stereo buses and four hardware inputs plus soundboard/process strips. One bus per output device; multichannel routing selects stereo pairs.
- 48 soundboard slots, five minutes per clip, 256 MB decoded audio. New imports are owned copies; older sessions may reference external paths.
- Standard WAV has a 4 GB limit. Recovery depends on the partial file and journal remaining available; arbitrary storage corruption is not repaired.
- Haunted Cavern's narrow treatment is included; its separate wide/convolution treatment and external measured impulse responses are not.
- Broadcast title is set at connection time. SHOUTcast v2 and dynamic metadata updates are not included. Some RTMP services require video. Feeding the encoder is not proof of public server reception.
- Driver channel counts are fixed at build time to 2 and 16. Other configurations require rebuilding and installing a driver.

## Reproducing validation

Use the README scripts from a logged-in macOS session with Core Audio access. UI checks need existing Accessibility access and audio stopped in the app. Installed-loopback checks need unused channels 15–16. Native tests do not capture a physical microphone or play test audio to speakers. Temporary TLS certificates, dummy credentials and generated audio stay in ignored Build directories and are excluded from release artifacts.


## Liquid Glass / shared-core regression — 2 November 2026

The redesigned packaged Mac app passed three launch cycles covering all nine sections, setup open/dismiss and normal quit. Shared mixer extraction passed 28 DSP/core checks and the same 28 under AddressSanitizer/UndefinedBehaviorSanitizer. Native integration passed, including a 15-second silent physical-output run with zero underruns or dropped frames. Actual window captures were refreshed for the website. This does not replace the hardware and distribution limitations above.
