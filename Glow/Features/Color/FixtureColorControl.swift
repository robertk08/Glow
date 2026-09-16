import SwiftUI

/// Colour control for one fixture.
///
/// The entry point the fixture screen composes; everything about how colour is
/// chosen lives behind it. Rendered inside a `Form`, so it produces `Section`s
/// rather than a container of its own.
///
/// The split is deliberate. Simple is a swatch, a name and two sliders, and it
/// never mentions an emitter: someone who wants the light warm and white gets
/// that in one tap, on a fixture whose amber die they have never heard of.
/// Advanced is every emitter with its DMX value, the fixture's own macro and
/// wheel bands by name, and a sentence saying which of them the fixture is
/// actually obeying.
struct FixtureColorControl: View {
    let control: FixtureControl
    /// Whether the person has asked for the full set of controls.
    var showsAdvanced: Bool = false

    private var model: FixtureColorModel { FixtureColorModel(control: control) }

    var body: some View {
        if model.canMix {
            ColorMixSection(model: model)
        }

        if model.canExpressTemperature {
            ColorTemperatureSection(model: model)
        }

        // The macro and wheel bands are the fixture's own colours. On a head
        // that has no emitters they are the only colour control there is, so
        // they come forward whether or not advanced is on.
        if !model.canMix || showsAdvanced {
            ForEach(model.bandedChannels) { channel in
                BandedColorSection(model: model, channel: channel, isPrimary: !model.canMix)
            }
        }

        if showsAdvanced, model.canMix {
            EmitterSection(model: model)
        }
    }
}

// MARK: - Simple

/// Swatch, presets, hue and saturation. No emitter is named anywhere in it.
///
/// Two stock sliders rather than a wheel or a `ColorPicker`. `ColorPicker`
/// opens the system panel, which carries brightness and opacity — a fixture
/// has neither, and the brightness there would fight the intensity control on
/// the screen above. A hue and a saturation slider are the same two numbers a
/// wheel carries, and they come with a readable value, VoiceOver adjustment
/// and large type for free, none of which a custom canvas would.
private struct ColorMixSection: View {
    let model: FixtureColorModel

    /// Remembered because a white has no hue to read back off the fixture.
    /// Without it, dragging saturation to zero and back would snap the light
    /// to red rather than returning the colour it started from.
    @State private var retainedHue: Double = 0.08

    @ScaledMetric(relativeTo: .title2) private var summarySize: CGFloat = 44

    var body: some View {
        Section {
            if let override = model.override {
                ColorOverrideBanner(model: model, override: override)
            }

            summary
            ColorPresetGrid(model: model)
            hueRow
            saturationRow
        } header: {
            Text("Colour")
        } footer: {
            Text(footer)
        }
        .onChange(of: model.renderedColor) { _, colour in
            if colour.saturation > 0.03 { retainedHue = colour.hue }
        }
    }

    // MARK: Rows

    private var summary: some View {
        HStack(spacing: 12) {
            ColorSwatch(light: model.renderedColor, size: summarySize)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.colorName)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current colour")
        .accessibilityValue("\(model.colorName), \(detail)")
    }

    /// The second line under the colour's name. Everything the swatch says in
    /// colour, said again in words.
    private var detail: String {
        if model.override != nil {
            return "Mix not in effect"
        }
        if model.level <= 0 {
            return "No emitter is up"
        }
        if let kelvin = model.kelvin {
            return "\(Int(kelvin.rounded())) K"
        }
        return "Hue \(Int((liveHue * 360).rounded()))°, \(Int((liveSaturation * 100).rounded()))% saturated"
    }

    private var hueRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hue")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(ColorVocabulary.hueName(liveHue))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(Int((liveHue * 360).rounded()))°")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)

            Slider(value: hueBinding, in: 0...1) {
                Text("Hue")
            }
            .tint(LightColor(hue: liveHue, saturation: 1).color)
            .accessibilityLabel("Hue")
            .accessibilityValue(ColorVocabulary.hueDescription(liveHue))
        }
    }

    private var saturationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Saturation")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(liveSaturation, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            Slider(value: saturationBinding, in: 0...1) {
                Text("Saturation")
            }
            .tint(LightColor(hue: liveHue, saturation: max(liveSaturation, 0.15)).color)
            .accessibilityLabel("Saturation")
            .accessibilityValue("\(Int((liveSaturation * 100).rounded())) percent")
        }
    }

    // MARK: Values

    private var liveHue: Double {
        let colour = model.renderedColor
        return colour.saturation > 0.03 ? colour.hue : retainedHue
    }

    private var liveSaturation: Double { model.renderedColor.saturation }

    private var hueBinding: Binding<Double> {
        Binding(
            get: { liveHue },
            set: { newValue in
                retainedHue = newValue
                // Dragging hue on a fixture that is currently a flat white
                // would otherwise do nothing visible at all, because there is
                // no saturation for the hue to colour. Give it enough of a
                // tint to see, and leave the saturation slider to take it
                // further.
                let saturation = liveSaturation < 0.08 ? 0.25 : liveSaturation
                model.apply(hue: newValue, saturation: saturation)
            }
        )
    }

    private var saturationBinding: Binding<Double> {
        Binding(
            get: { liveSaturation },
            set: { model.apply(hue: liveHue, saturation: $0) }
        )
    }

    // MARK: Footer

    private var footer: String {
        var sentences: [String] = []

        if model.override != nil {
            sentences.append(model.authorityStatement)
        }

        let names = model.mixableRoles.map { $0.localizedName.lowercased() }
        if !names.isEmpty {
            sentences.append("Mixed from this fixture's \(names.formatted(.list(type: .and))) emitters.")
        }

        if model.hasUltraviolet {
            sentences.append("Its UV emitter is left out of the mix — it is nearly invisible, so it has its own preset instead.")
        }

        sentences.append("Colour and brightness are separate here: none of this changes how bright the fixture is.")

        return sentences.joined(separator: " ")
    }
}

/// What the fixture is obeying instead of the mix, and one tap to undo it.
///
/// This is the trap the brief is about. A macro channel a few points off zero
/// silently wins over every colour fader, and nothing on the fixture, the
/// manual or the desk says so until half an hour has gone.
private struct ColorOverrideBanner: View {
    let model: FixtureColorModel
    let override: ColorOverride

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text(model.authorityStatement)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if override.release != nil {
                Button("Hand colour back to the mix", systemImage: "arrow.uturn.backward") {
                    withAnimation(.snappy) { model.release(override) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var headline: String {
        switch override.kind {
        case .macro: "A colour macro is in charge, not the mix"
        case .wheel: "The colour wheel is filtering the beam"
        }
    }
}

// MARK: - Colour temperature

/// Warm to cool, for the fixtures that can mean it.
private struct ColorTemperatureSection: View {
    let model: FixtureColorModel

    /// Only consulted when the fixture is showing a colour rather than a
    /// white, where there is no temperature to read back.
    @State private var storedKelvin: Double = ColorTemperature.neutral

    var body: some View {
        Section {
            if let channel = model.temperatureChannel {
                dedicated(channel)
            } else {
                mixed
            }
        } header: {
            Text("White balance")
        } footer: {
            Text(footer)
        }
    }

    // MARK: Mixed from emitters

    private var kelvin: Double { model.kelvin ?? storedKelvin }

    private var mixed: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(ColorVocabulary.whiteName(kelvin: kelvin))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(kelvin.rounded())) K")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            Slider(value: kelvinBinding, in: ColorTemperature.range, step: 50) {
                Text("Colour temperature")
            } minimumValueLabel: {
                Image(systemName: "thermometer.sun")
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "thermometer.snowflake")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Colour temperature")
            .accessibilityValue("\(Int(kelvin.rounded())) kelvin, \(ColorVocabulary.whiteName(kelvin: kelvin).lowercased())")

            // The slider reads back off the fixture whenever the fixture is
            // showing a white. When it is not, the number above is the last
            // one asked for rather than a description of anything, and saying
            // so is better than letting it look like a readout.
            if model.kelvin == nil {
                Label(unappliedNote, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var unappliedNote: String {
        model.level <= 0
            ? "Nothing is up on this fixture. Moving this lights it as a white."
            : "The fixture is showing a colour, not a white. Moving this puts it back on white."
    }

    private var kelvinBinding: Binding<Double> {
        Binding(
            get: { kelvin },
            set: { newValue in
                storedKelvin = newValue
                model.apply(kelvin: newValue)
            }
        )
    }

    // MARK: A fixture with its own channel for it

    private func dedicated(_ channel: FixtureChannel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(channel.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(Int(model.control.value(of: channel)), format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            Slider(value: model.control.binding(for: channel), in: 0...255, step: 1) {
                Text(channel.name)
            } minimumValueLabel: {
                Image(systemName: "thermometer.sun")
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "thermometer.snowflake")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(channel.name)
            .accessibilityValue("\(Int(model.control.value(of: channel))) of 255")
        }
    }

    private var footer: String {
        if model.temperatureChannel != nil {
            // No profile in the library carries the Kelvin either end of such
            // a channel, and guessing would put a number on the screen that
            // the fixture disagrees with.
            return "This fixture has a channel of its own for white balance. Which Kelvin each end lands on is the fixture's business — its manual prints the figures."
        }

        var sentence = "Spends the white emitter first and fills in with red, green and blue"
        if model.mixableRoles.contains(.amber) {
            sentence = "Spends the white and amber emitters first and fills in with red, green and blue"
        }
        return sentence + ", which is how a warm white comes out warm rather than orange. The level does not move."
    }
}
