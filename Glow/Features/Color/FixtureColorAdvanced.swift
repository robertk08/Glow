import SwiftUI

/// Every emitter the fixture has, with its DMX value and its address.
///
/// The simple controls above never name an emitter; this is where someone who
/// wants a specific amount of amber, or who is reading values off the
/// fixture's own display, gets at them. The footer is the statement of which
/// control the fixture is currently obeying, which belongs next to the faders
/// it might be overruling.
struct EmitterSection: View {
    let model: FixtureColorModel

    var body: some View {
        Section {
            ForEach(model.emitterChannels) { channel in
                EmitterFader(model: model, channel: channel)
            }
        } header: {
            Text("Emitters")
        } footer: {
            Text(model.authorityStatement)
        }
    }
}

/// One emitter: a chip of its colour, its name, its DMX value, its address.
struct EmitterFader: View {
    let model: FixtureColorModel
    let channel: FixtureChannel

    @ScaledMetric(relativeTo: .subheadline) private var chipSize: CGFloat = 14

    private var value: Double { Double(model.control.value(of: channel)) }
    private var address: DMXAddress? { model.control.address(of: channel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // A chip rather than a tinted slider. `mixingTint` gives white
                // for the white emitter, and a white slider track is invisible
                // in a light-mode form; a bordered chip reads in both
                // appearances and sits right next to the emitter's name, so
                // the colour is never the only thing carrying it.
                Circle()
                    .fill(chipColor)
                    .overlay { Circle().strokeBorder(.separator, lineWidth: 0.5) }
                    .frame(width: chipSize, height: chipSize)

                Text(channel.name)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(Int(value), format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: value))
            }
            .accessibilityHidden(true)

            Slider(value: model.control.binding(for: channel), in: 0...255, step: 1) {
                Text(channel.name)
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue("\(Int(value)) of 255")

            if let address {
                Text("DMX \(address.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var chipColor: Color {
        Emitter.light(of: channel.role)?.color ?? channel.role.mixingTint ?? .secondary
    }

    private var accessibilityLabel: String {
        guard let address else { return channel.name }
        return "\(channel.name), DMX \(address.rawValue)"
    }
}

// MARK: - Macro and wheel bands

/// A colour channel whose manual describes bands rather than a mix.
///
/// Two quite different jobs behind one view. On a wash with emitters this is
/// the thing that can silently overrule them, and the section exists to make
/// that visible and reversible. On a beam head or a laser there is no mix at
/// all — the bands *are* every colour the fixture has, and this is the colour
/// control.
struct BandedColorSection: View {
    let model: FixtureColorModel
    let channel: FixtureChannel
    /// True when the fixture has no emitters, so these bands are all there is.
    let isPrimary: Bool

    private var value: UInt8 { model.control.value(of: channel) }
    private var activeBand: FixtureChannelRange? { channel.range(containing: value) }

    /// A band that resets the head or strikes a lamp is not a colour choice.
    /// Those are reachable from the fixture's own settings list, which asks
    /// before sending them; putting them in a colour menu would make a stray
    /// tap in a colour picker reset a head mid-show.
    private var selectableBands: [FixtureChannelRange] {
        channel.ranges.filter { !$0.requiresConfirmation }
    }

    var body: some View {
        Section {
            if !selectableBands.isEmpty {
                Picker(channel.name, selection: bandBinding) {
                    ForEach(selectableBands) { band in
                        Text(band.label).tag(Optional(band))
                    }

                    // The fixture can be sitting on a value no band claims —
                    // another desk left it there, or the profile has a gap.
                    // Without a matching tag the picker would show nothing.
                    if activeBand == nil || activeBand?.requiresConfirmation == true {
                        Text("Value \(Int(value))").tag(FixtureChannelRange?.none)
                    }
                }
            }

            if let band = walkableBand {
                position(in: band)
            } else if channel.ranges.isEmpty {
                position(in: FixtureChannelRange(from: 0, to: 255, label: channel.name, kind: .proportional))
            }

            if let override = model.override, override.channel == channel, override.release != nil {
                Button("Hand colour back to the mix", systemImage: "arrow.uturn.backward") {
                    withAnimation(.snappy) { model.release(override) }
                }
            }
        } header: {
            Text(channel.role == .colorWheel ? "Colour wheel" : "Colour macro")
        } footer: {
            Text(footer)
        }
    }

    // MARK: Rows

    private var bandBinding: Binding<FixtureChannelRange?> {
        Binding(
            get: { activeBand.flatMap { $0.requiresConfirmation ? nil : $0 } },
            set: { band in
                guard let band else { return }
                withAnimation(.snappy) {
                    model.control.setValue(band.representativeValue, of: channel)
                }
            }
        )
    }

    /// A band wide enough to hold more than one thing.
    ///
    /// The profiles describe "Colour macro" as a single band 224 values wide
    /// and the wheel's slots as one 118 wide, because nobody has typed out
    /// what each step inside them is. A fader scoped to the band is the only
    /// way to reach those colours, and it is also where the DMX value for the
    /// one you like is legible enough to write down.
    private var walkableBand: FixtureChannelRange? {
        guard let activeBand, Int(activeBand.to) - Int(activeBand.from) >= 16 else { return nil }
        return activeBand
    }

    private func position(in band: FixtureChannelRange) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(band.kind == .proportional ? band.label : "Position in this band")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(Int(value), format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { model.control.setValue(UInt8($0.rounded().clamped(to: 0...255)), of: channel) }
                ),
                in: Double(band.from)...Double(band.to),
                step: 1
            ) {
                Text(band.label)
            }
            .accessibilityLabel(band.label)
            .accessibilityValue("\(Int(value)), within \(band.from) to \(band.to)")
        }
    }

    // MARK: Footer

    private var footer: String {
        guard isPrimary else { return model.authorityStatement }

        let source =
            channel.role == .colorWheel
            ? "This fixture makes colour with glass in the beam, not by mixing emitters, so these positions are every colour it has."
            : "This fixture has no colour faders — its built-in colours are all it can do."

        let named = channel.ranges.contains { Int($0.to) - Int($0.from) >= 16 }
        let unnamed = named
            ? " The wide bands hold several colours the profile does not name; the fader walks through them and shows the DMX value of the one you land on."
            : ""

        return source + unnamed
    }
}
