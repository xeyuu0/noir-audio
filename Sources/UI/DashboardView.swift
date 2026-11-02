// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var model: StudioModel
    @EnvironmentObject var telemetry: EngineTelemetry
    var body: some View {
        Panel(title: "The live mix", subtitle: model.running ? "MAIN OUTPUT  ·  LIVE" : "MAIN OUTPUT  ·  PAUSED") {
            WaveformView(samples: model.waveform, running: model.running).frame(height: 160)
            HStack(spacing: 30) {
                MeterView(peak: model.peaks[0], rms: model.rms[0], label: "MICROPHONE")
                MeterView(peak: model.peaks[6], rms: model.rms[6], label: "MAIN OUTPUT")
            }
        }
        HStack(alignment: .top, spacing: 20) {
            Panel(title: "Signal path", subtitle: "01 → 02 → 03") {
                signal("01", "INPUT", model.device(model.session.channels[0].deviceUID)?.name ?? "No microphone", "mic")
                Divider().overlay(Noir.line)
                signal("02", "PROCESSING", model.session.channels[0].effects ? model.session.name : "Clean signal · effects bypassed", "waveform.path")
                Divider().overlay(Noir.line)
                signal("03", "DESTINATION", model.device(model.session.buses[0].deviceUID)?.name ?? "Choose a Main output", "arrow.up.forward")
                Button("Edit routing") { model.selectedSection = .mixer }.buttonStyle(SecondaryButtonStyle())
            }
            VStack(spacing: 20) {
                Panel(title: "Your voice", subtitle: "PRESET") {
                    Picker("Preset", selection: Binding(get: { model.session.name }, set: { model.preset($0) })) { ForEach(Session.presetNames, id: \.self) { Text($0) } }.labelsHidden()
                    InfoRow(title: "Noise isolation", value: model.session.channels[0].effects && model.session.effects[0].values[0] > 0 ? "Enabled" : "Bypassed")
                    InfoRow(title: "Monitor", value: model.device(model.session.buses[1].deviceUID)?.name ?? "No output")
                    Button("Open voice effects") { model.selectedSection = .effects }.buttonStyle(SecondaryButtonStyle())
                }
                Panel(title: "Master level") {
                    ValueSlider(title: "Main output", value: model.busBinding(0, \.volume), range: 0...1.5, step: 0.01)
                    HStack { Text("−∞"); Spacer(); Text("0 dB"); Spacer(); Text("+3.5 dB") }.font(.system(size: 9, design: .monospaced)).foregroundStyle(Noir.secondary)
                }
            }
        }
        HStack(spacing: 16) {
            metric("AUDIO CPU", String(format: "%.1f", model.cpu), "%", "Master callback budget")
            metric("PIPELINE ESTIMATE", String(format: "%.1f", model.latency), "ms", "Excludes converter / acoustic delay")
            metric("SAMPLE RATE", "48", "kHz", "Device rates converted independently")
            metric("BUFFER HEALTH", "\(model.underruns)", "", "Underrun events")
        }
    }
    private func signal(_ n: String, _ label: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: 16) { Image(systemName: symbol).font(.system(size: 18, weight: .light)).frame(width: 40, height: 40).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading, spacing: 5) { Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Noir.secondary); Text(detail).font(.system(size: 12, weight: .medium)).lineLimit(2) }; Spacer(); Text(n).font(.system(size: 11, design: .monospaced)).foregroundStyle(Noir.secondary) }
    }
    private func metric(_ title: String, _ value: String, _ unit: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Noir.secondary); HStack(alignment: .firstTextBaseline, spacing: 4) { Text(value).font(.system(size: 26, weight: .light, design: .monospaced)); Text(unit).font(.system(size: 12)).foregroundStyle(Noir.secondary) }; Text(caption).font(.system(size: 9)).foregroundStyle(Noir.secondary).frame(height: 25, alignment: .topLeading) }.padding(18).frame(maxWidth: .infinity, alignment: .leading).modifier(GlassSurface())
    }
}
