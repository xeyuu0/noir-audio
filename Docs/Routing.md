# Routing workflows

Start with headphones and low levels. In Settings, select a connected physical output as the clock device. Main, Monitor, Aux 2 and Aux 3 are independent mixes; their device assignments and enabled source sends both matter.

## Processed voice and soundboard to Discord, Zoom or OBS

1. Install the NOIR drivers through Virtual Devices if they are not detected, then restart macOS.
2. In Audio Mixer, select the physical microphone on Input 1. Choose the desired channel pair.
3. Assign Main to NOIR Microphone and Monitor to headphones. Enable Microphone → Main. Optionally enable Microphone → Monitor to hear the processed signal.
4. In Voice Effects, select Input 1, enable its effects and select a mask, room or processing preset.
5. Press Start audio. Grant microphone permission when macOS requests it. Observe the input and Main meters.
6. In the receiving app, select NOIR Microphone as its input and the physical headphones as its output. Use the receiving app's own input test to confirm reception.
7. For clips, import audio into Soundboard and enable Soundboard → Main. Its volume and Monitor send are independent of the microphone.

Do not route the chat app's received audio into the Main mix sent back to that chat. Automatic feedback prevention blocks sending a hardware input back to the same selected device, but it cannot identify every multi-application feedback loop.

## Selected application audio

Open Application Audio, refresh the application list, select the intended source and press Start selected capture. macOS controls system-audio recording permission. Enable Application → Main or another destination in the routing matrix.

The selected app remains audible through its normal output. Capturing it and also sending its captured audio to the same headphones can double monitoring. Protected audio may be silent. Apps with multiple helper processes may require a dedicated loopback route for complete output.

## Logic Pro through loopback

1. In Logic Pro's audio settings, select NOIR Loopback as the output device. Keep the intended physical microphone/interface selected as Logic's input when recording there.
2. Route Logic's stereo output to channels 1–2, or another stereo pair on the loopback device.
3. In NOIR, choose NOIR Loopback on an available hardware input strip and select the same pair.
4. Enable that strip's Monitor send to hear Logic through NOIR's headphones. Enable its Main send if Logic should also reach a chat app or the Main recording mix.
5. Keep Main assigned to NOIR Microphone. Never return the Logic loopback input to NOIR Loopback.

For simultaneous microphone and Logic audio, route their separate input strips into Main. For recording only, leave a bus without a hardware destination and select that bus in Recorder. Process-tap capture is an alternative when supported, but the loopback path makes channel assignments explicit.

## Recording and replay

Recorder selects Main, Monitor, either Aux, the microphone before effects or the processed microphone. The microphone-only record sources are before its channel fader/mute. Choose a destination and start recording after audio is running. WAV files are stereo, 48 kHz, 24-bit PCM. Stop & save closes the recording; Reveal in Finder opens its location.

Replay keeps 5–120 seconds of the selected source in memory. Save replay writes that audio to WAV. Changing the source or duration clears the replay buffer. After stopping a recording, Export AAC creates a 192 kbps M4A copy through native AVFoundation. Active takes use a `.partial.wav` and recovery journal; reopening NOIR repairs and finalizes complete frames after an interruption when those files remain available. Standard WAV takes stop at the 4 GB size limit.

## Independent broadcast mix

Use Aux 3 as a broadcast mix, enabling only its intended source sends. It can remain disconnected from a hardware output. Select it in Broadcasting, choose a separately installed FFmpeg executable and enter the server details.

| Protocol | Endpoint form | Codec/container |
| --- | --- | --- |
| Icecast | `icecast://host:port/mount` or `icecasts://host:port/mount` | MP3, AAC/ADTS or Opus/Ogg as supported by the server |
| SHOUTcast v1 | `shoutcast://host:source-port` | MP3; source port is commonly listener port + 1 |
| RTMP / RTMPS | `rtmp://host/app/key` or `rtmps://host/app/key` | AAC/FLV, audio only |

Set credentials, bitrate and title, then connect. Verify server acceptance and playback at a separate listener. Audio-only RTMP is incompatible with services that require a video track. NOIR's encoder activity indicator alone is not proof of reception. Isolated local Icecast, SHOUTcast-compatible and RTMP(S) receivers passed decoding, reconnection and failure tests. Public internet services still require their own validation.

## Troubleshooting

- If launching an older copy still fails, quit it and open the rebuilt `dist/NOIR Audio.app` by its full path. The fixed build keeps live telemetry outside SwiftUI's scene/menu state.
- If a microphone is silent, check macOS permission, device/channel pair, mute/solo, source sends and the destination device. A meter on an internal bus does not prove another application is receiving it.
- If a virtual endpoint is missing, use Check again, inspect Audio MIDI Setup, then use Install / repair and restart if needed.
- If a device disconnects, reconnect it and inspect the selected UIDs and channel pairs before restarting audio. A replaced device may have a new UID.
- If audio breaks up, increase the requested buffer, inspect underrun/drop counters and check DSP lookahead and device rates. Test at matched rates before introducing independent device clocks.
- If the app cannot save settings, inspect access to its Application Support folder. Preserve `Session.json` before resetting or replacing it.

## Assets, shortcuts, and TLS

New soundboard imports are copied into NOIR's session asset folder. Replace keeps a pad's ID and playback settings; Remove deletes only NOIR's owned copy. The first nine visible pads use Option-Command-1 through 9. Escape stops all clips while NOIR is active. Settings lets you customize audio, mute, deafen, recording and replay shortcuts and explicitly enable them globally. Global combinations use physical US-layout key positions.

Secure Icecast and RTMPS verify server certificates and hostnames. The default trust store comes from the selected FFmpeg build. For a private server, Custom certificate authority selects its trusted PEM authority. Credentials remain in memory and raw encoder stderr never appears in UI diagnostics. A sufficiently privileged local process inspector can see encoder command-line arguments.
