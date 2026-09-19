import SwiftUI

struct ColorControl: View {
	let programmer: Programmer
	
	@State private var showsEmitters = false
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
	
	var body: some View {
		Section {
			if let channel = programmer.macroChannel {
				BandPicker(programmer: programmer, channel: channel, bands: channel.ranges)
				
				if let active = programmer.adjustableBand(of: channel) {
					Slider(value: programmer.binding(channel), in: Double(active.from)...Double(active.to)) {
						Text(channel.name)
					}
				}
			}
			
			if programmer.macroOverridesMix {
				Button("Use the color mixer") {
					programmer.releaseMix()
				}
			}
			
			ColorPicker("Any color", selection: programmer.colorBinding, supportsOpacity: false)
			
			LazyVGrid(columns: columns, spacing: 12) {
				ForEach(programmer.presets) { preset in
					Button {
						programmer.apply(preset)
					} label: {
						Swatch(colors: [preset.swatch], isSelected: programmer.selectedPresetID == preset.id)
					}
					.buttonStyle(.plain)
					.accessibilityLabel(preset.name)
					.accessibilityAddTraits(programmer.selectedPresetID == preset.id ? .isSelected : [])
				}
			}
			.padding(.vertical, 4)
			
			if programmer.balancesWhite {
				VStack(alignment: .leading) {
					LabeledContent("White balance", value: "\(Int(programmer.kelvin)) K")
					
					Slider(value: Binding { programmer.kelvin } set: { programmer.apply(kelvin: $0) }, in: ColorTemperature.range, neutralValue: ColorTemperature.neutral) {
						Text("White balance")
					} minimumValueLabel: {
						Image(systemName: "thermometer.sun")
					} maximumValueLabel: {
						Image(systemName: "thermometer.snowflake")
					}
				}
			}
			
			DisclosureGroup(programmer.isSubtractive ? "Filters" : "Emitters", isExpanded: $showsEmitters) {
				ForEach(programmer.emitterChannels) { channel in
					VStack(alignment: .leading, spacing: 6) {
						LabeledContent(channel.name) {
							Text("\(programmer.value(of: channel))")
								.monospacedDigit()
								.foregroundStyle(.secondary)
						}
						.font(.subheadline)
						
						Slider(value: programmer.binding(channel), in: 0...255, neutralValue: Double(channel.defaultValue)) {
							Text(channel.name)
						}
						.tint(channel.role.color)
					}
				}
			}
		} header: {
			Text("Color")
		} footer: {
			if programmer.macroOverridesMix {
				Text("This light is showing a built-in color, so the mixer is doing nothing.")
			} else if programmer.isSubtractive {
				Text("This head makes color by putting filters in front of a white lamp, so the dimmer sets how bright it is.")
			}
		}
	}
}
