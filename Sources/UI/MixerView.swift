// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct DevicePicker: View {
    var label: String
    var devices: [AudioDevice]
    @Binding var selection: String
    var body: some View { Picker(label, selection: $selection) { Text("Not connected").tag(""); ForEach(devices) { Text($0.name).tag($0.uid) }; if !selection.isEmpty && !devices.contains(where: { $0.uid == selection }) { Text("Device unavailable").tag(selection) } }.pickerStyle(.menu).labelsHidden().help(label).accessibilityLabel(label) }
}
struct MixerView: View {
    @EnvironmentObject var model: StudioModel
    @EnvironmentObject var telemetry: EngineTelemetry
    var body: some View {
        HStack { Text("INPUTS").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(Noir.secondary); Spacer(); Button("Open preset…", action: model.loadPreset); Button("Save preset…", action: model.savePreset) }.buttonStyle(SecondaryButtonStyle())
        HStack(alignment: .top, spacing: 14) { ForEach(0..<4) { ChannelStrip(index: $0) } }
        HStack(alignment: .top, spacing: 14) { ChannelStrip(index: 4); ChannelStrip(index: 5) }
        Panel(title: "Routing matrix", subtitle: "INDEPENDENT SENDS  /  MIX-MINUS") {
            Grid(horizontalSpacing: 24, verticalSpacing: 14) {
                GridRow { Text("SOURCE → OUTPUT").font(.system(size: 9, design: .monospaced)).foregroundStyle(Noir.secondary).frame(maxWidth: .infinity, alignment: .leading); ForEach(model.session.buses) { Text($0.name).font(.system(size: 11, weight: .medium)).frame(width: 75) } }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(model.session.channels) { c in
                    GridRow { Text(c.name).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading); ForEach(0..<4) { b in
                        Toggle("\(c.name) to \(model.session.buses[b].name)", isOn: Binding(get: { model.session.channels[c.id].sends[b] > 0 }, set: { model.setRoute(source: c.id, bus: b, on: $0) })).labelsHidden().toggleStyle(.checkbox).frame(width: 75)
                    } }
                }
            }
            Text("Keep voice-chat return audio out of Main. A source cannot return to the same loopback device. Enable Monitor sends only when using headphones.").font(.system(size: 11)).foregroundStyle(Noir.secondary)
        }
        HStack(alignment: .top, spacing: 14) { ForEach(0..<4) { b in
            Panel(title: model.session.buses[b].name, subtitle: String(format: "%02d", b + 1)) {
                DevicePicker(label: "\(model.session.buses[b].name) output device", devices: model.outputDevices, selection: model.busBinding(b, \.deviceUID, routing: true))
                if let device = model.device(model.session.buses[b].deviceUID), device.outputs > 2 {
                    Picker("Channels", selection: model.busBinding(b, \.pair, routing: true)) { ForEach(0..<(device.outputs / 2), id: \.self) { Text("\($0 * 2 + 1)–\($0 * 2 + 2)").tag($0) } }
                }
                MeterView(peak: model.peaks[b + 6], rms: model.rms[b + 6], label: "OUTPUT")
                ValueSlider(title: "Level", value: model.busBinding(b, \.volume), range: 0...1.5, step: 0.01)
                Toggle("Mute", isOn: model.busBinding(b, \.mute)).toggleStyle(.checkbox)
            }
        } }
    }
}
struct ChannelStrip: View {
    @EnvironmentObject var model: StudioModel
    @EnvironmentObject var telemetry: EngineTelemetry
    var index: Int
    var body: some View {
        Panel(title: "", subtitle: "") {
            HStack { Text(String(format: "%02d", index + 1)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Noir.secondary); Spacer(); Image(systemName: index == 4 ? "square.grid.3x3" : index == 5 ? "macwindow" : "waveform") }
            TextField("Channel name", text: model.channelBinding(index, \.name)).textFieldStyle(.plain).font(.system(size: 15, weight: .medium))
            if index < 4 {
                DevicePicker(label: "Input \(index + 1) device", devices: model.inputDevices, selection: model.channelBinding(index, \.deviceUID, routing: true))
                if let device = model.device(model.session.channels[index].deviceUID), device.inputs > 2 {
                    Picker("Channels", selection: model.channelBinding(index, \.pair, routing: true)) { ForEach(0..<((device.inputs + 1) / 2), id: \.self) { Text("\($0 * 2 + 1)–\(min(device.inputs, $0 * 2 + 2))").tag($0) } }
                }
            } else { Text(index == 4 ? "Native file playback" : model.capturing ? "Selected application capture" : "No application captured").font(.system(size: 11)).foregroundStyle(Noir.secondary) }
            MeterView(peak: model.peaks[index], rms: model.rms[index], label: "POST FADER")
            ValueSlider(title: "Input gain", value: model.channelBinding(index, \.gain), range: -24...24, unit: " dB")
            ValueSlider(title: "Level", value: model.channelBinding(index, \.volume), range: 0...1.5, step: 0.01)
            ValueSlider(title: "Balance", value: model.channelBinding(index, \.balance), range: -1...1, step: 0.01)
            HStack { Toggle("Mute", isOn: model.channelBinding(index, \.mute)); Spacer(); Toggle("Solo", isOn: model.channelBinding(index, \.solo)) }.toggleStyle(.checkbox).font(.system(size: 11))
            Toggle("Effects chain", isOn: model.channelBinding(index, \.effects)).toggleStyle(.checkbox).font(.system(size: 11))
        }
    }
}
