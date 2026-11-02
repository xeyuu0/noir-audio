// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

enum Noir {
    static let background = Color(white: 5.0 / 255)
    static let surface = Color(white: 16.0 / 255)
    static let elevated = Color(white: 25.0 / 255)
    static let secondary = Color(white: 190.0 / 255)
    static let line = Color.white.opacity(0.13)
}
// One material vocabulary for the entire studio. Audio telemetry never drives its animation.
struct GlassSurface: ViewModifier {
    var radius: CGFloat = 18
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        surface(content)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(contrast == .increased ? 0.6 : 0.28), .white.opacity(0.06), .white.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.18), radius: 14, x: 0, y: 7)
    }
    @ViewBuilder private func surface(_ content: Content) -> some View {
        if reduceTransparency {
            content.background(Noir.elevated, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(.black.opacity(0.22)).interactive(interactive), in: .rect(cornerRadius: radius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white).fontWeight(.semibold)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.white.opacity(configuration.isPressed ? 0.22 : 0.1), in: Capsule())
            .modifier(GlassSurface(radius: 24, interactive: true))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(.white.opacity(enabled ? 0.94 : 0.4))
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.02), in: RoundedRectangle(cornerRadius: 11))
            .modifier(GlassSurface(radius: 11, interactive: enabled))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
struct NoirBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if !reduceTransparency { WindowMaterial() }
            Color(white: 0.025).opacity(reduceTransparency ? 1 : 0.86)
            if !reduceTransparency {
                GeometryReader { geometry in
                    Ellipse().fill(.white.opacity(0.12)).frame(width: geometry.size.width * 0.7, height: 220)
                        .blur(radius: 90).rotationEffect(.degrees(-22)).offset(x: geometry.size.width * 0.28, y: -100)
                    Ellipse().fill(.white.opacity(0.07)).frame(width: 600, height: 360)
                        .blur(radius: 100).offset(x: -220, y: geometry.size.height * 0.55)
                }
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct WindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            view?.window?.isOpaque = false
            view?.window?.backgroundColor = .clear
        }
    }
}
struct Panel<Content: View>: View {
    var title: String
    var subtitle: String = ""
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !title.isEmpty { HStack(alignment: .firstTextBaseline) { Text(title).font(.system(size: 15, weight: .semibold)); Spacer(); if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Noir.secondary) } } }
            content
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassSurface())
    }
}
struct Tag: View {
    var text: String
    var active = false
    var body: some View { Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1).padding(.horizontal, 10).padding(.vertical, 6).background(active ? Color.white.opacity(0.16) : Color.white.opacity(0.06), in: Capsule()).foregroundStyle(active ? Color.white : Noir.secondary) }
}
struct MeterView: View {
    var peak: Float
    var rms: Float = 0
    var label: String = ""
    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(Color.white.opacity(0.38)).frame(width: geo.size.width * level(peak))
                    Capsule().fill(Color.white.opacity(0.9)).frame(width: geo.size.width * level(rms))
                }
            }.frame(height: 5)
            if !label.isEmpty { HStack { Text(label); Spacer(); Text(peak > 0.00001 ? String(format: "%.1f dB", 20 * log10(peak)) : "−∞ dB") }.font(.system(size: 10, design: .monospaced)).foregroundStyle(Noir.secondary) }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(label.isEmpty ? "Audio level" : label).accessibilityValue(peak > 0.00001 ? "\(Int(20 * log10(peak))) decibels" : "Silent")
    }
    private func level(_ x: Float) -> Double { x > 0 ? Double(max(0, min(1, (20 * log10(x) + 60) / 60))) : 0 }
}
struct WaveformView: View {
    var samples: [Float]
    var running: Bool
    var body: some View {
        Canvas { context, size in
            for line in 0...4 {
                let y = size.height * CGFloat(line) / 4
                var grid = Path(); grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); context.stroke(grid, with: .color(.white.opacity(0.055)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
            }
            var path = Path()
            for (i, sample) in samples.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(max(1, samples.count - 1)), y: size.height * (0.5 - CGFloat(max(-1, min(1, sample))) * 0.46))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(.white.opacity(running ? 0.9 : 0.25)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }.accessibilityLabel(running ? "Live Main output waveform" : "Waveform paused")
    }
}
struct ValueSlider: View {
    var title: String
    @Binding var value: Float
    var range: ClosedRange<Float>
    var unit = ""
    var step: Float = 1
    var body: some View {
        VStack(spacing: 9) {
            HStack { Text(title).font(.system(size: 12)); Spacer(); Text(String(format: step < 1 ? "%.2f%@" : "%.0f%@", value, unit)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Noir.secondary) }
            Slider(value: $value, in: range, step: step).accessibilityLabel(title)
        }
    }
}
struct InfoRow: View {
    let title: String
    let value: String
    var body: some View { HStack(alignment: .firstTextBaseline) { Text(title).foregroundStyle(Noir.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.system(size: 12)) }
}
extension StudioModel {
    func binding<T>(_ key: WritableKeyPath<Session, T>, update: (() -> Void)? = nil) -> Binding<T> {
        Binding(get: { self.session[keyPath: key] }, set: { self.session[keyPath: key] = $0; (update ?? self.syncControls)() })
    }
    func channelBinding<T>(_ index: Int, _ key: WritableKeyPath<ChannelState, T>, routing: Bool = false) -> Binding<T> {
        Binding(get: { self.session.channels[index][keyPath: key] }, set: { self.session.channels[index][keyPath: key] = $0; routing ? self.routingChanged() : self.syncControls() })
    }
    func busBinding<T>(_ index: Int, _ key: WritableKeyPath<BusState, T>, routing: Bool = false) -> Binding<T> {
        Binding(get: { self.session.buses[index][keyPath: key] }, set: { self.session.buses[index][keyPath: key] = $0; routing ? self.routingChanged() : self.syncControls() })
    }
    func effectBinding(_ source: Int, _ parameter: Int) -> Binding<Float> {
        Binding(get: { self.session.effects[source].values[parameter] }, set: { self.session.effects[source].values[parameter] = $0; self.prepareEffects() })
    }
}
