import SwiftUI

/// Colour control for one fixture.
///
/// The entry point the fixture screen composes; everything about how colour is
/// chosen lives behind it. Rendered inside a `Form`, so it produces `Section`s
/// rather than a container of its own.
struct FixtureColorControl: View {
    let control: FixtureControl
    /// Whether the person has asked for the full set of controls.
    var showsAdvanced: Bool = false

    var body: some View {
        if control.supportsColor {
            Section("Colour") {
                ColorPicker("Mix", selection: control.colorBinding, supportsOpacity: false)

                HStack(spacing: 8) {
                    ForEach(Self.quickColors, id: \.name) { swatch in
                        Button {
                            withAnimation(.snappy) { control.color = swatch.color }
                        } label: {
                            Circle()
                                .fill(swatch.color)
                                .frame(height: 30)
                                .overlay { Circle().strokeBorder(.separator) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(swatch.name)
                    }
                }

                ForEach(control.auxiliaryColorChannels) { channel in
                    ChannelFader(
                        title: channel.name,
                        subtitle: nil,
                        tint: channel.role.mixingTint,
                        value: control.binding(for: channel)
                    )
                }
            }
        }
    }

    private static let quickColors: [(name: String, color: Color)] = [
        ("White", .white), ("Red", .red), ("Amber", .orange), ("Yellow", .yellow),
        ("Green", .green), ("Cyan", .cyan), ("Blue", .blue),
        ("Magenta", Color(red: 1, green: 0, blue: 1)),
    ]
}
