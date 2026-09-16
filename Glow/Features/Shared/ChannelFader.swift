import SwiftUI

/// One channel as a labelled fader with a live DMX readout.
///
/// The raw 0-255 value is always visible. Anyone patching a rig is reading
/// values off the fixture's own display, and a percentage that has to be
/// converted back in your head is worse than useless when the head is not
/// doing what you expect.
struct ChannelFader: View {
    let title: String
    let subtitle: String?
    var tint: Color?
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...255

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(Int(value.rounded()), format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: value))
            }

            Slider(value: $value, in: range, step: 1) {
                Text(title)
            }
            .tint(tint)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(Int(value.rounded()))"))
    }
}

/// A fader for a normalised 0...1 parameter, shown as a percentage.
struct LevelFader: View {
    let title: String
    var systemImage: String?
    var tint: Color?
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(title).font(.subheadline.weight(.medium))
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: value))
            }
            Slider(value: $value, in: 0...1) { Text(title) }
                .tint(tint)
        }
        .accessibilityElement(children: .combine)
    }
}
