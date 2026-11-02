# Windows validation

Port created 2 November 2026. This log records the test boundary, not a claim of production readiness.

- The 28 existing DSP/core tests pass on the Mac host through the portable adapter. The DSP algorithms remain the original OctopusEAX code.
- Portable session validation, PCM16/24/32 conversion, WAV recovery and replay tests pass on the Mac host.
- Windows x64 native application and test binaries cross-compile with MinGW-w64.
- A Windows GitHub Actions job builds with MSVC, runs the same DSP/core tests and portable-service tests, tests Media Foundation decode/AAC export and recording, then launches every native UI page without enabling audio. Its actual result is recorded after the run completes.

Pending hardware validation: WASAPI capture/render on real endpoints, endpoint unplug/reconnect, process/system capture, virtual-cable reception in Discord/OBS/DAWs, multiple clocks and device rates, Bluetooth, sleep/wake, public streaming servers, and performance soak tests. No hardware result is inferred from a compile or headless CI result. Builds are unsigned previews.
