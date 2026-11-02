# NOIR Audio for Windows

A native C++20 / Win32 / WASAPI port sharing NOIR’s actual mixer, resamplers, OctopusEAX room algorithms, 42 voice masks and effects with the Mac app. Windows 10 (1703 or newer) / Windows 11, x64. Application-specific loopback needs Windows 11. The UI uses Windows controls; it does not embed a browser.

## Install and route audio

Run the per-user setup executable, or extract the portable ZIP and open `NOIR Audio.exe`. These preview builds are **unsigned**. Windows may show an unknown-publisher/SmartScreen warning. Verify the published SHA-256 before deciding whether to run it. No driver is installed by the application installer.

1. Open Routing. Refresh devices and choose a microphone and an output clock.
2. Assign Main to your intended output. Leave microphone monitoring disabled unless wearing headphones.
3. To send the mix to Discord, OBS, or a DAW, separately install a Windows virtual cable from its vendor, such as [VB-CABLE](https://vb-audio.com/Cable/). Choose **CABLE Input** as the Main output in NOIR and **CABLE Output** as the input in the receiving app.
4. Enable sends in the routing matrix and press Start audio. Each endpoint may serve one output bus. Additional independent buses require additional endpoints or virtual cables.
5. Stop audio before changing endpoint assignments or the application capture source.

System capture cannot use an output endpoint assigned to a NOIR bus, avoiding direct capture/playback recursion. Keep chat return audio out of the Main send. The macOS NOIR/BlackHole drivers are not compatible with Windows and are not included in this installer.

## Included

- Four hardware inputs, soundboard and loopback/application input; four independent stereo buses with level, gain, balance, mute, solo, sends, meters and a peak limiter.
- Event-driven WASAPI with independently resampled endpoints. Unsupported formats and unavailable endpoints fail visibly. An unplug stops audio; select a replacement and restart explicitly.
- Shared effects, configurable stage order, seven-band EQ, filters and compression.
- 48 soundboard pads, four pages, local Media Foundation decoding, loop/level/fade controls, managed copies; five minutes per clip and 256 MB decoded audio total.
- PCM24 WAV recording, crash-recoverable partial takes, 5–120 second replay and AAC export.
- Icecast MP3 and RTMP(S) AAC broadcasting through an explicitly selected external `ffmpeg.exe`, with bounded pipes and cancelable process supervision. TLS certificates are verified. Credentials are never saved to sessions or logs. The status reports encoder delivery; it does not pretend to confirm remote server acceptance.
- Session import/export, seven presets, configurable global shortcuts (opt-in) and local shortcuts. Sessions and clips are kept in `%LOCALAPPDATA%\NOIR Audio`.

SHOUTcast v1, ASIO, native Windows virtual drivers, 32-bit Windows and Windows on ARM packages and automatic device/broadcast reconnection are not included. Windows N editions need the Media Feature Pack. Codec availability follows the installed Windows Media Foundation codecs. Mac and Windows presets use different device identifiers and are not interchangeable. Exported sessions refer to clips already present in the managed Clips folder; they are not self-contained clip archives.

## Build on Windows

Install Visual Studio 2022 Build Tools with Desktop development with C++ and CMake 3.24+.

```powershell
cmake -S . -B Build/windows -A x64
cmake --build Build/windows --config Release --parallel 4
ctest --test-dir Build/windows -C Release --output-on-failure
& 'Build/windows/Windows/Release/NOIR Audio.exe' --ui-smoke
```

The GUI executable is `Build/windows/Windows/Release/NOIR Audio.exe`. `NoirWindowsTests.exe --devices` enumerates endpoints without starting audio. The default tests decode/export generated audio locally; they do not access a microphone or play tones. `--ui-smoke` uses an isolated temporary session, visits all nine pages and exits with a result in `windows-ui-smoke.log`.

For cross-compilation, install MinGW-w64 and CMake, then run `bash Scripts/build-windows.sh`. Install NSIS to compile the per-user setup executable using `bash Scripts/package-windows.sh`.

## Validation boundary

See [Windows validation](../Docs/WindowsValidation.md) for actual results. CI covers DSP, services, Media Foundation and window creation/navigation. Physical microphones, virtual cables, sample-rate drift, Bluetooth, sleep/wake and third-party applications still require a Windows hardware test. A successful cross-build or CI test is not evidence of those scenarios.
