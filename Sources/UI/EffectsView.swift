// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct EffectsView: View {
    @EnvironmentObject var model: StudioModel
    @State private var source = 0
    private let stages = ["Noise isolation", "Voice & formant", "Voice speed", "Equalizer", "Filters", "Compressor", "Reverb"]
    var body: some View {
        HStack { Picker("Source", selection: $source) { ForEach(model.session.channels) { Text($0.name).tag($0.id) } }.frame(width: 280); Spacer(); Toggle("Enable effects", isOn: model.channelBinding(source, \.effects)).toggleStyle(.switch) }
        HStack(alignment: .top, spacing: 20) {
            Panel(title: "Signal chain", subtitle: "LIVE ORDER") {
                ForEach(Array(model.session.effects[source].order.enumerated()), id: \.element) { position, stage in
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", position + 1)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Noir.secondary)
                        Toggle(stages[Int(stage)], isOn: Binding(get: { Int(model.session.effects[source].values[21]) & (1 << stage) == 0 }, set: { on in let bits = Int(model.session.effects[source].values[21]); model.session.effects[source].values[21] = Float(on ? bits & ~(1 << stage) : bits | (1 << stage)); model.prepareEffects() })).toggleStyle(.checkbox).font(.system(size: 12))
                        Spacer()
                        Button { move(position, -1) } label: { Image(systemName: "chevron.up") }.disabled(position == 0).accessibilityLabel("Move \(stages[Int(stage)]) earlier")
                        Button { move(position, 1) } label: { Image(systemName: "chevron.down") }.disabled(position == 6).accessibilityLabel("Move \(stages[Int(stage)]) later")
                    }.buttonStyle(.borderless).padding(.vertical, 8)
                }
                Text("Reorder or bypass stages while audio runs. Changes crossfade into a prepared chain. Spectral isolation and pitch shifting introduce lookahead.").font(.system(size: 11)).foregroundStyle(Noir.secondary)
                Button("Save custom preset…", action: model.savePreset).buttonStyle(SecondaryButtonStyle())
            }.frame(minWidth: 300, maxWidth: 360)
            VStack(spacing: 20) {
                Panel(title: "Voice character", subtitle: "OCTOPUSEAX DSP") {
                    Picker("Mask", selection: model.effectBinding(source, 2)) { Text("Natural voice").tag(Float(-1)); ForEach(0..<Int(NAMaskCount()), id: \.self) { Text(String(cString: NAMaskName(Int32($0)))).tag(Float($0)) } }
                    ValueSlider(title: "Pitch offset", value: model.effectBinding(source, 3), range: -150...150, unit: " Hz")
                    ValueSlider(title: "Vocal size / formant", value: model.effectBinding(source, 4), range: 60...150, unit: "%")
                    ValueSlider(title: "Voice speed", value: model.effectBinding(source, 5), range: 50...150, unit: "%")
                    Toggle("Preserve pitch when changing speed", isOn: Binding(get: { model.session.effects[source].values[22] != 0 }, set: { model.session.effects[source].values[22] = $0 ? 1 : 0; model.prepareEffects() })).toggleStyle(.checkbox)
                }
                Panel(title: "Noise isolation") {
                    Picker("Mode", selection: model.effectBinding(source, 0)) { ForEach(Array(["Bypass", "Gate", "Clean", "Studio", "Broadcast", "Vocal expander"].enumerated()), id: \.offset) { i, title in Text(title).tag(Float(i)) } }
                    ValueSlider(title: "Strength", value: model.effectBinding(source, 1), range: 0...100, unit: "%")
                    Text("Clean, Studio and Broadcast use the original spectral suppressor. Vocal expander provides a faster gate with voice tone shaping.").font(.system(size: 11)).foregroundStyle(Noir.secondary)
                }
            }
        }
        Panel(title: "Seven-band equalizer", subtitle: "±12 dB") {
            Toggle("Enable EQ", isOn: Binding(get: { model.session.effects[source].values[8] != 0 }, set: { model.session.effects[source].values[8] = $0 ? 1 : 0; model.prepareEffects() })).toggleStyle(.checkbox)
            HStack(spacing: 20) { ForEach(0..<7) { i in ValueSlider(title: ["125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz"][i], value: model.effectBinding(source, i + 9), range: -12...12, unit: " dB") } }
        }
        HStack(alignment: .top, spacing: 20) {
            Panel(title: "Environment", subtitle: "15 ORIGINAL ROOMS") {
                Picker("Room", selection: model.effectBinding(source, 6)) { Text("Off").tag(Float(-1)); ForEach(0..<Int(NARoomCount()), id: \.self) { Text(String(cString: NARoomName(Int32($0)))).tag(Float($0)) } }
                ValueSlider(title: "Wet / dry", value: model.effectBinding(source, 7), range: 0...1, step: 0.01)
                Text("Haunted Cavern uses the original narrow CardCore microphone treatment. External measured impulse responses and the separate wide headphone treatment are not bundled.").font(.system(size: 11)).foregroundStyle(Noir.secondary)
            }
            Panel(title: "Dynamics & filters") {
                ValueSlider(title: "High-pass (0 = off)", value: model.effectBinding(source, 16), range: 0...500, unit: " Hz", step: 10)
                ValueSlider(title: "Low-pass", value: model.effectBinding(source, 17), range: 1000...20000, unit: " Hz", step: 100)
                ValueSlider(title: "Threshold", value: model.effectBinding(source, 18), range: -48...0, unit: " dB")
                ValueSlider(title: "Ratio (1 = off)", value: model.effectBinding(source, 19), range: 1...12, unit: ":1", step: 0.5)
                ValueSlider(title: "Makeup gain", value: model.effectBinding(source, 20), range: 0...18, unit: " dB")
                Text("All output buses include a stereo-linked −0.18 dBFS safety peak limiter.").font(.system(size: 11)).foregroundStyle(Noir.secondary)
            }
        }
    }
    private func move(_ index: Int, _ direction: Int) { model.session.effects[source].order.swapAt(index, index + direction); model.prepareEffects() }
}
