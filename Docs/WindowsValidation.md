# Windows validation

Port created 2 November 2026. This log records the test boundary, not a claim of production readiness.

- The 28 existing DSP/core tests pass on the Mac host through the portable adapter. The DSP algorithms remain the original OctopusEAX code.
- Portable session validation, PCM16/24/32 conversion, WAV recovery and replay tests pass on the Mac host.
- Windows x64 native application and test binaries cross-compile with MinGW-w64.
- A Windows GitHub Actions job builds with MSVC, runs the same DSP/core tests and portable-service tests, tests Media Foundation decode/AAC export and recording, then launches every native UI page without enabling audio. Run [41520623229](https://github.com/xeyuu0/noir-audio/actions/runs/41520623229), commit `b2bdf81bc07f08893adcbef169351b7a1185b56e`: the Windows job passed compilation, all three CTest suites, and UI navigation across all nine pages. The tests do not use a microphone or play sound.

Pending hardware validation: WASAPI capture/render on real endpoints, endpoint unplug/reconnect, process/system capture, virtual-cable reception in Discord/OBS/DAWs, multiple clocks and device rates, Bluetooth, sleep/wake, public streaming servers, and performance soak tests. No hardware result is inferred from a compile or headless CI result. Builds are unsigned previews.


Distribution provenance: the Windows setup and portable ZIP embed the **exact MSVC executable from the successful Windows job** above. The downloaded CI artifact SHA-256 was verified (`0c0b7174c15d9a87490384628e73c9310b0bb452a5bbda7f109a10b3a562af05`). The package includes BUILD-INFO.txt with the executable hash and source commit. The per-user NSIS installer was compiled on the Mac; clean Windows install/upgrade/uninstall validation remains separate from the verified executable launch and services.
