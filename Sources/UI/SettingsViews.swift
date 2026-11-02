// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import ServiceManagement

struct DriverView: View {
    @EnvironmentObject var model: StudioModel
    @State private var removeConfirmation = false
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            driver("Virtual microphone", "mic", model.virtualMic, "Choose this as the microphone in Discord, Zoom, OBS, or another recording application.")
            driver("Loopback input", "arrow.triangle.2.circlepath", model.loopback, "Send a DAW or application's output here, then receive its channel pairs in the mixer.")
        }
        Panel(title: "System driver setup", subtitle: "POWERED BY BLACKHOLE") {
            Text("The HAL driver is a separate system component. Installation opens macOS Installer and requires administrator authorization. Quit audio applications first; restart your Mac after installing so Core Audio loads the new endpoints.").font(.system(size: 13)).foregroundStyle(Noir.secondary)
            HStack {
                Button("Install / repair NOIR drivers…") { do { try DriverManager.install() } catch { model.error = error.localizedDescription } }
                Button("Check again", action: model.refreshDevices)
                Button("Audio MIDI Setup") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app")) }
            }.buttonStyle(SecondaryButtonStyle())
            Text("The installer provides a stereo microphone and a 16-channel loopback. Choose channel pairs in the mixer. Existing BlackHole devices also work. No kernel extension or security-setting changes are needed.").font(.system(size: 12)).foregroundStyle(Noir.secondary)
            Divider()
            Button("Remove NOIR drivers…") { removeConfirmation = true }.buttonStyle(SecondaryButtonStyle())
            Text("Removal affects only NOIRMicrophone.driver and NOIRLoopback.driver. Existing BlackHole and other audio drivers stay installed.").font(.system(size: 11)).foregroundStyle(Noir.secondary)
        }
        .confirmationDialog("Remove NOIR's two system audio drivers?", isPresented: $removeConfirmation) {
            Button("Remove drivers") { model.stopAudio(); do { try DriverManager.remove(); model.notice = "NOIR drivers removed. Restart your Mac to unload them." } catch { model.error = error.localizedDescription } }
        } message: { Text("Quit audio applications first. macOS will request administrator authorization, and a restart is required.") }
        Panel(title: "Discord + headphones") {
            Text("1. Main → NOIR Microphone. Monitor → your headphones.\n2. Enable Microphone → Main in the routing matrix. Enable Microphone → Monitor to hear your processed voice.\n3. In Discord, select NOIR Microphone as input and your headphones as output. Keep Discord's output out of Main.\n4. Add Soundboard → Main when you want clips in voice chat.").font(.system(size: 13)).lineSpacing(8).foregroundStyle(Noir.secondary)
            Button("Use recommended voice routing") { model.session.buses[0].deviceUID = model.virtualMic?.uid ?? ""; model.session.buses[1].deviceUID = model.session.clockUID; model.preset("Discord Voice"); model.routingChanged() }.disabled(model.virtualMic == nil)
        }
    }
    private func driver(_ title: String, _ icon: String, _ device: AudioDevice?, _ detail: String) -> some View {
        Panel(title: title, subtitle: device == nil ? "NOT DETECTED" : "AVAILABLE") {
            Image(systemName: icon).font(.system(size: 30, weight: .ultraLight)).padding(.vertical, 8)
            Text(device?.name ?? "Set up your endpoint").font(.system(size: 18, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(Noir.secondary).frame(minHeight: 45, alignment: .topLeading)
            if let device { InfoRow(title: "Channels", value: "\(device.inputs) in / \(device.outputs) out"); InfoRow(title: "Device clock", value: "\(Int(device.rate)) Hz") }
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var model: StudioModel
    @EnvironmentObject var telemetry: EngineTelemetry
    @AppStorage("showMenuBar") private var showMenuBar = true
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Panel(title: "Audio engine") {
                Text("Clock / headphone device").font(.system(size: 12))
                DevicePicker(label: "Clock device", devices: model.outputDevices.filter { !$0.isVirtual }, selection: model.binding(\.clockUID, update: model.routingChanged))
                Picker("Buffer request", selection: model.binding(\.bufferFrames, update: model.routingChanged)) { ForEach([64, 128, 256, 512, 1024], id: \.self) { Text("\($0) frames").tag($0) } }
                InfoRow(title: "Internal processing", value: "48,000 Hz · Float32 stereo")
                InfoRow(title: "Clock-device actual buffer", value: "\(model.device(model.session.clockUID)?.buffer ?? 0) frames")
                Text("Smaller buffers reduce latency and leave less CPU time. Devices may choose a different buffer length. Independent sources use adaptive sample-rate conversion.").font(.system(size: 11)).foregroundStyle(Noir.secondary)
                Button("Restore audio defaults", action: model.resetAudio).buttonStyle(SecondaryButtonStyle())
            }
            Panel(title: "Application") {
                Toggle("Menu bar controls", isOn: $showMenuBar).toggleStyle(.checkbox)
                Toggle("Launch at login", isOn: $loginEnabled).toggleStyle(.checkbox).onChange(of: loginEnabled) { _, on in do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { model.error = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled } }
                Button("Run setup assistant") { model.showSetup = true }.buttonStyle(SecondaryButtonStyle())
                Button("Microphone permissions") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }.buttonStyle(SecondaryButtonStyle())
                Button("Open settings folder") { NSWorkspace.shared.open(SessionStore.directory) }.buttonStyle(SecondaryButtonStyle())
                Text("Audio starts only when you press Start audio. Application capture always requires an explicit source selection. Sessions stay on this Mac.").font(.system(size: 11)).foregroundStyle(Noir.secondary)
            }
        }
        Panel(title: "Diagnostics", subtitle: "LIVE ENGINE TELEMETRY") {
            InfoRow(title: "Master callback budget", value: String(format: "%.2f%%", model.cpu))
            InfoRow(title: "Software latency estimate", value: String(format: "%.2f ms", model.latency))
            InfoRow(title: "Underrun events", value: "\(model.underruns)")
            InfoRow(title: "Dropped queue frames", value: "\(model.overruns)")
            InfoRow(title: "Frames limited at output", value: "\(model.clipped)")
            Text("The latency estimate includes source buffering, converter lookahead and selected DSP lookahead. It is not a measured round trip. Use a cable loopback and cross-correlation to measure the complete path. Voice speed has variable additional delay.").font(.system(size: 11)).foregroundStyle(Noir.secondary)
            Button("Export diagnostics…") {
                let panel = NSSavePanel(); panel.nameFieldStringValue = "NOIR Diagnostics.txt"; guard panel.runModal() == .OK, let url = panel.url else { return }
                let text = "NOIR Audio 0.1\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)\nCPU budget: \(model.cpu)%\nLatency estimate: \(model.latency) ms\nUnderruns: \(model.underruns)\nDropped frames: \(model.overruns)\nLimited frames: \(model.clipped)\n" + model.devices.map { "\($0.name): \($0.inputs) in, \($0.outputs) out, \($0.rate) Hz, \($0.buffer) frames" }.joined(separator: "\n")
                do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { model.error = error.localizedDescription }
            }
        }
        Panel(title: "Keyboard shortcuts") {
            ForEach(StudioAction.allCases) { action in
                HStack {
                    Text(action.label).font(.system(size: 12)); Spacer()
                    Picker("Modifiers for \(action.label)", selection: Binding(get: { model.shortcut(action).modifiers }, set: { model.setShortcut(action, modifiers: $0) })) {
                        ForEach(ShortcutModifiers.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().frame(width: 110)
                    Picker("Key for \(action.label)", selection: Binding(get: { model.shortcut(action).key }, set: { model.setShortcut(action, key: $0) })) {
                        ForEach(StudioShortcut.keyCodes.keys.sorted(), id: \.self) { Text($0.uppercased()).tag($0) }
                    }.labelsHidden().frame(width: 70)
                }
            }
            Toggle("Use these shortcuts in other apps", isOn: Binding(get: { model.keyboard.global }, set: model.enableGlobalShortcuts)).toggleStyle(.checkbox)
            Text(model.shortcutStatus).font(.system(size: 11)).foregroundStyle(Noir.secondary)
            InfoRow(title: "Soundboard / stop all", value: "⌥⌘1–9 / Escape")
            Text("Soundboard keys address the first nine visible pads and work while NOIR is active. Global shortcuts use physical US-layout key positions.").font(.system(size: 11)).foregroundStyle(Noir.secondary)
        }
        Panel(title: "NOIR Audio", subtitle: "0.1.0 · DEVELOPMENT RELEASE") {
            Text("Native SwiftUI + Core Audio · Apple Silicon\nOriginal OctopusEAX DSP by Freemasonry (MIT). BlackHole HAL driver by Existential Audio (GPLv3). NOIR original code is GPL-3.0-or-later.").font(.system(size: 12)).foregroundStyle(Noir.secondary)
            HStack { ForEach(["OctopusEAX-LICENSE", "BlackHole-LICENSE"], id: \.self) { name in Button(name.replacingOccurrences(of: "-LICENSE", with: " license")) { if let url = Bundle.main.url(forResource: name, withExtension: "txt") { NSWorkspace.shared.open(url) } } } }.buttonStyle(SecondaryButtonStyle())
        }
    }
}
struct SetupView: View {
    @EnvironmentObject var model: StudioModel
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack { Image(systemName: "waveform").font(.system(size: 28, weight: .light)); Spacer(); Tag(text: "WELCOME TO NOIR") }
            Text("A little setup.\nA lot of possibility.").font(.system(size: 34, weight: .light))
            Text("Connect your microphone, choose headphones, and give your sound a destination.").font(.system(size: 13)).foregroundStyle(Noir.secondary)
            VStack(alignment: .leading, spacing: 16) {
                Text("01   YOUR MICROPHONE").font(.system(size: 10, design: .monospaced)).foregroundStyle(Noir.secondary)
                DevicePicker(label: "Microphone", devices: model.inputDevices, selection: model.channelBinding(0, \.deviceUID))
                Text("02   YOUR HEADPHONES / CLOCK").font(.system(size: 10, design: .monospaced)).foregroundStyle(Noir.secondary)
                DevicePicker(label: "Headphones", devices: model.outputDevices.filter { !$0.isVirtual }, selection: model.binding(\.clockUID))
                Text("03   YOUR VIRTUAL MICROPHONE").font(.system(size: 10, design: .monospaced)).foregroundStyle(Noir.secondary)
                HStack { Text(model.virtualMic?.name ?? "Driver setup required"); Spacer(); Button("Driver setup") { model.showSetup = false; model.selectedSection = .virtual } }
            }
            Text("Microphone permission is requested when you start audio. Monitoring starts off to avoid speaker feedback. Use headphones before enabling it in the mixer.").font(.system(size: 12)).foregroundStyle(Noir.secondary)
            HStack { Button("Later") { model.showSetup = false }; Spacer(); Button("Enter the studio") { model.session.setupComplete = true; model.session.buses[1].deviceUID = model.session.clockUID; model.persist(); model.showSetup = false } .buttonStyle(PrimaryButtonStyle()) }
        }.padding(36).frame(width: 530).background { NoirBackdrop() }.modifier(GlassSurface(radius: 28)).tint(.white).preferredColorScheme(.dark).saturation(0)
    }
}
