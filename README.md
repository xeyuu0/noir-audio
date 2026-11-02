# NOIR Audio

Native audio studio for Apple Silicon Macs and Windows x64, built with SwiftUI / Core Audio and Win32 / WASAPI around a shared C++20 processing core. This is a **0.1 development release** with a working audio engine, mixer, DSP, soundboard, recoverable WAV recorder, native AAC export, process-tap capture, customizable shortcuts and optional broadcasting. See [validation and remaining work](Docs/Validation.md) before treating it as a production release.

[Website and downloads](https://noir-audio-orpin.vercel.app) · [Windows setup and build guide](Windows/README.md) · [Windows validation](Docs/WindowsValidation.md)

The Mac interface uses native Liquid Glass on macOS 26+, including panels, navigation, transport and setup. Reduce Transparency uses opaque surfaces; Reduce Motion disables navigation and press animations. Earlier supported macOS versions use native materials.

## Open the Mac app

The local build is `dist/NOIR Audio.app`. Open that copy after a rebuild:

```sh
open 'dist/NOIR Audio.app'
```

Audio starts only when **Start audio** is pressed. Choose the microphone and headphone clock in setup. Use **Audio Mixer** to assign Main to NOIR Microphone and Monitor to headphones. Enable Monitor sends only when you want to hear those sources. The application's **Virtual Devices** section provides driver detection, installation, repair and removal.

The launch crash reported on 31 October was fixed by separating meter telemetry from application scene state and deferring the initial setup sheet. The packaged application passed three launch/navigation/setup cycles on 2 November. The regression tests are included.

## Build

Requirements: Apple Silicon, macOS 14.2 or later, Xcode with the macOS 26 SDK or newer for compiling the Liquid Glass branch, and XcodeGen. The verified host uses Xcode 27.1 and macOS 27.2. Earlier supported macOS versions use native material backgrounds and have not yet been tested.

The complete upstream source snapshots are included under `ThirdParty`; no dependency download is needed for the build.

```sh
bash Scripts/build-drivers.sh
bash Scripts/build.sh
```

The first command builds two distinct BlackHole-based HAL drivers and their installer, then copies the installer into app resources. The second regenerates the Xcode project, builds Release, copies the app to `dist`, and verifies its ad-hoc signature. Build logs are in `Build`.

Open `NOIR Audio.xcodeproj` to develop in Xcode. Change shared settings in `project.yml`, because XcodeGen regenerates the project.

## Virtual devices and permissions

`dist/NOIR Audio Drivers.pkg` installs a stereo **NOIR Microphone** and a 16-channel **NOIR Loopback** in `/Library/Audio/Plug-Ins/HAL`. Installation requires macOS administrator authorization. Quit audio applications before installation and restart afterward. It does not change the system default audio devices. The app can also use existing compatible BlackHole endpoints.

Use **Virtual Devices → Remove NOIR drivers…** to remove the two NOIR bundles and their installer receipt, then restart. Removal does not delete other vendors' drivers. Driver installation and removal are separate from copying the `.app` into Applications.

Microphone access is requested when starting with an input selected. Application capture uses a selected Core Audio process tap and requires macOS system-audio recording permission. Permission failures appear in the app; capture does not start automatically. Microphone audio and saved sessions stay local unless you route them to another application or explicitly start broadcasting.

See [routing workflows](Docs/Routing.md) for Discord, soundboard, recording, Logic Pro and broadcasts.

## Tests

```sh
bash Scripts/test.sh             # DSP, resampling, mixer, queues, render allocation checks
bash Scripts/test-drivers.sh     # In-process upstream HAL ring tests, without installation
bash Scripts/test-native.sh      # Real output clock, silent hardware, recording/replay/decoding
bash Scripts/test-launch.sh      # Scene-state isolation while actual HAL callbacks run
bash Scripts/test-ui-launch.sh   # Packaged app, navigation, setup, normal quit/relaunch
bash Scripts/test-reliability.sh # Interrupted takes, AAC, clip management, device recovery
bash Scripts/test-shortcuts.sh   # Global registration, conflicts, persistence and cleanup
bash Scripts/test-broadcast.sh   # Local listeners, TLS, failures, reconnect, stalled encoder
bash Scripts/test-virtual.sh     # Installed loopback signal, channel order and latency
bash Scripts/test-sanitizers.sh  # AddressSanitizer and UndefinedBehaviorSanitizer
```

Native tests require a logged-in macOS session with access to an available output device. The UI test requires existing Accessibility access for its launcher and the packaged app with audio stopped. It does not grant permissions or change routing. It leaves the app open on Dashboard. Logs are under `Tests/Results`.

The audio integration test routes a low-level generated tone into an internal disconnected bus; physical output receives silence. Set `NOIR_STABILITY_SECONDS=60` or longer to extend the native stability run.

## Packaging and licenses

```sh
bash Scripts/build-windows.sh
bash Scripts/package-windows.sh
bash Scripts/package-macos-dmg.sh
bash Scripts/package.sh
```

These scripts create a Mac disk image and app ZIP, a Windows per-user setup executable and portable ZIP, the matching source archive, and SHA-256 checksums. The Windows packaging script requires NSIS. The local app and driver bundles use ad-hoc signatures; the installer is unsigned and artifacts are **not notarized**. Developer ID Application/Installer credentials and an Apple notarization account are required for a public signed release. No such signing identity was available for this build.

NOIR's original code is GPL-3.0-or-later. BlackHole's original GPL license and OctopusEAX's MIT license accompany the full source and the app. Distribute the matching source archive and notices with binary releases. See [source audit](Docs/SourceAudit.md) for upstream commits and porting details. LadioCast is a functional reference; its proprietary code and assets are not used.

Broadcasting uses a separately installed FFmpeg executable, selected in the app. FFmpeg is not included in these archives. Its codec support and licensing depend on the chosen build.

Additional documentation: [architecture](Docs/Architecture.md), [routing](Docs/Routing.md), [test evidence and limitations](Docs/Validation.md).

## Extended tests and website

The virtual test sends generated audio only through NOIR Loopback channels 15–16, leaving NOIR Microphone untouched. Ensure that pair is unused, then set `NOIR_STABILITY_SECONDS=1800` for a 30-minute release stability run. Broadcasting tests require FFmpeg, Icecast and OpenSSL at the paths in `Tests/BroadcastServers.py`; generated signals and temporary certificates stay on localhost. No external streaming service is contacted.

`Website/` contains the multipage monochrome glass product site, real app screenshots, native page transitions, setup/release pages and browser checks. Run `python3 Website/build.py` before packaging to regenerate its shared page chrome and artwork. Run `bash Scripts/prepare-website.sh` after packaging to prepare real app, driver, source and checksum downloads. See [website instructions](Website/README.md).
