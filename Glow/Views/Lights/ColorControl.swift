import SwiftUI

struct ColorControl: View {
    let control: FixtureControl

    @State private var hue: Double = 0
    @State private var saturation: Double = 1

    private var emitters: [ChannelRole] { control.profile.emitterChannels.map(\.role) }
    private var presets: [ColorPreset] { ColorPreset.all(for: emitters) }

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        Section {
            if control.macroOverridesMix {
                Button("Use the colour mixer") {
                    control.releaseMix()
                }
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(presets) { preset in
                    Button {
                        control.apply(preset.mix(with: emitters))
                        syncSliders()
                    } label: {
                        Circle()
                            .fill(preset.swatch(with: emitters).color)
                            .frame(height: 44)
                            .overlay {
                                Circle().strokeBorder(.separator)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                }
            }
            .padding(.vertical, 4)

            Slider(value: $hue, in: 0...1) {
                Text("Hue")
            }
            .onChange(of: hue) { applyHueSaturation() }

            Slider(value: $saturation, in: 0...1) {
                Text("Saturation")
            } minimumValueLabel: {
                Image(systemName: "circle")
            } maximumValueLabel: {
                Image(systemName: "circle.fill")
            }
            .onChange(of: saturation) { applyHueSaturation() }
        } header: {
            Text("Colour")
        } footer: {
            if control.macroOverridesMix {
                Text("This light is showing a built-in colour, so the mixer is doing nothing.")
            }
        }
        .task { syncSliders() }
    }

    private func applyHueSaturation() {
        control.apply(.mixing(LightColor(hue: hue, saturation: saturation), with: emitters))
    }

    private func syncSliders() {
        let light = control.mix.light.normalised
        hue = light.hue / 360
        saturation = light.saturation
    }
}
