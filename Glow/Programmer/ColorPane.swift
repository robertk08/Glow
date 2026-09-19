import SwiftUI

struct ColorPane: View {
	let programmer: Programmer
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]
	
	var body: some View {
		VStack(spacing: 12) {
			if programmer.macroOverridesMix {
				ContentUnavailableView {
					Label("Built-in Color", systemImage: "paintpalette")
				} description: {
					Text("This light is showing a color built into the fixture, so the mixer is doing nothing.")
				} actions: {
					Button("Use the Color Mixer") {
						programmer.releaseMix()
					}
					.buttonStyle(.glassProminent)
				}
				.frame(height: 232)
			} else {
				ColorPad(light: programmer.lightBinding, isActive: programmer.isActive(.color))
				
				LazyVGrid(columns: columns, spacing: 10) {
					ForEach(programmer.presets) { preset in
						Button {
							programmer.apply(preset)
						} label: {
							Swatch(colors: [preset.swatch], size: 40, isSelected: programmer.selectedPresetID == preset.id)
						}
						.buttonStyle(.plain)
						.accessibilityLabel(preset.name)
						.accessibilityAddTraits(programmer.selectedPresetID == preset.id ? .isSelected : [])
					}
				}
			}
		}
	}
}
