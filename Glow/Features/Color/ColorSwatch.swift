import SwiftUI

/// A round chip of one colour.
///
/// Never shown on its own. Whatever uses it puts a name beside it, and the
/// "this one is selected" mark is a tick rather than a change of hue, because
/// a swatch grid you can only read by colour is exactly the grid that is
/// useless to the people most likely to be running lights from the side of a
/// dark stage.
struct ColorSwatch: View {
    let light: LightColor
    var isSelected = false
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(light.color)
            Circle()
                // Keeps a white swatch from vanishing into a light-mode form,
                // and a near-black one from vanishing into a dark-mode one.
                .strokeBorder(.separator, lineWidth: 1)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(light.contrastingInk)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The colours worth one tap, as a grid that survives large type.
struct ColorPresetGrid: View {
    let model: FixtureColorModel

    @ScaledMetric(relativeTo: .caption) private var swatchSize: CGFloat = 42
    @State private var taps = 0

    private var presets: [ColorPreset] { ColorPreset.all(for: model.mixableRoles) }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: swatchSize + 26), spacing: 10, alignment: .top)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(presets) { preset in
                swatch(preset)
            }
        }
        // On the tap, not on the colour: the hue slider changes the same
        // values forty times a second and has no business buzzing the phone.
        .sensoryFeedback(.selection, trigger: taps)
    }

    private func swatch(_ preset: ColorPreset) -> some View {
        let light = preset.swatch(with: model.mixableRoles)
        let isShowing = model.isShowing(preset)

        return Button {
            taps += 1
            withAnimation(.snappy) { model.apply(preset) }
        } label: {
            VStack(spacing: 5) {
                ColorSwatch(light: light, isSelected: isShowing, size: swatchSize)
                Text(preset.name)
                    .font(.caption2)
                    .fontWeight(isShowing ? .semibold : .regular)
                    .foregroundStyle(isShowing ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isShowing ? [.isButton, .isSelected] : .isButton)
    }
}
