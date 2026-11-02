# Upstream inspection — 31 October 2026

Inspection preceded application implementation. Full source checkouts are preserved under ThirdParty.

## OctopusEAX

Repository: https://github.com/ALMASONYH/OctopusEAX
Commit: ba67b419905a15b87f532c35fab1707ad4d0124c
MIT, copyright (c) 2026 Freemasonry. Original license accompanies the sources and app resources.

The Windows application combines Win32/GDI UI, WASAPI capture/render, COM/Media Foundation decoding, virtual-cable installation and DSP orchestration in a 13,763-line app.cpp. Playback, process capture, file export, hotkeys and device setup depend on Windows. They cannot be compiled as native macOS features. No Windows binaries or branding are reused.

Portable header-only modules include the EAX delay network, CardCore, all 15 room parameter tables, 42 mask tables, PSOLA VoiceShaper, VoiceFx, tempo processing, spectral VoiceIsolator, ExpanderGate, seven-band biquad EQ, convolution FFT and mixing helpers. NOIR includes these original headers directly, rather than substituting approximate algorithms. Preparation and vector allocation must happen outside callbacks. VoiceShaper has a fixed 2,600-frame delay; spectral isolation and speed processing add their own lookahead. Original app.cpp also allocates/rebuilds effects during audio processing; that orchestration is not reused.

The Haunted Cavern original app has separate narrow/wide output treatments, a special CardCore and loud stage, optional external convolution measurements, and non-linear amount laws. The native port must distinguish original algorithms from any differences in application-level routing. External measured impulse responses are not included in the upstream source checkout.

## BlackHole

Repository: https://github.com/ExistentialAudio/BlackHole
Commit: 574029f0d3175ccf29a826d74be4da3967b1cb92
GPLv3; copyright (C) 2019 Existential Audio Inc. See the original LICENSE and source headers.

The AudioServerPlugIn implementation lives in BlackHole/BlackHole.c. Core Audio loads a CFPlugIn factory exposing device, stream and control objects. Float32 samples pass through a shared frame-indexed ring. Zero timestamps use the Mach host clock; rate changes use HAL configuration-change notifications. Compile-time definitions select channel count, names, UID identity, visibility, mirror endpoints and sample rates. The driver contains its own mutexes and synchronization; it is a separate system component, not a SwiftUI plug-in.

NOIR builds two distinct driver identities: a 2-channel virtual microphone and a 16-channel loopback. Separate identities prevent accidental microphone return loops and allow a DAW to feed loopback while a chat app receives the mix. Driver bundles require installation in /Library/Audio/Plug-Ins/HAL. macOS administrator authorization and a Core Audio reload/restart are real deployment steps. No SIP changes or kernel extensions are involved. The app detects existing BlackHole devices as well.

The upstream developer guide states that non-GPLv3 projects require a separate license. This project chooses GPL-3.0-or-later for original code and carries the upstream GPL driver source, MIT notices and reproducible build scripts. A proprietary distribution requires resolving commercial licensing with Existential Audio; it is not implied by use of a separate bundle.

## LadioCast

Functional reference only: https://apps.apple.com/us/app/ladiocast/id411213048
The documented mixer has four inputs, Main plus three Aux outputs, per-input sends, channel-pair mapping, independent clocks and optional network streamers. NOIR uses original SwiftUI layouts and original routing code. No proprietary source, assets, or branding are copied. Protocol compatibility requires server-level integration tests, not simply displaying connection controls.
