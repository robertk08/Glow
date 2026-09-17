import SwiftUI

struct ColorControl: View {
	let programmer: Programmer
	
	@State private var kelvin: Double = ColorTemperature.neutral
	@State private var showsEmitters = false
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
	
	var body: some View {
		Section {
			if programmer.macroOverridesMix {
				Button("Use the colour mixer") {
					programmer.releaseMix()
				}
			}
			
			ColorPicker("Any colour", selection: programmer.colorBinding, supportsOpacity: false)
			
			LazyVGrid(columns: columns, spacing: 12) {
				ForEach(programmer.presets) { preset in
					Button {
						programmer.apply(preset)
					} label: {
						Circle()
							.fill(preset.swatch.color)
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
			
			if programmer.balancesWhite {
				VStack(alignment: .leading) {
					LabeledContent("White balance", value: "\(Int(kelvin)) K")
					
					Slider(value: $kelvin, in: ColorTemperature.range, neutralValue: ColorTemperature.neutral) {
						Text("White balance")
					} minimumValueLabel: {
						Image(systemName: "thermometer.sun")
					} maximumValueLabel: {
						Image(systemName: "thermometer.snowflake")
					}
					.onChange(of: kelvin) {
						programmer.apply(kelvin: kelvin)
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
						
						Slider(value: programmer.binding(channel), in: 0...255, step: 1, neutralValue: Double(channel.defaultValue)) {
							Text(channel.name)
						}
						.tint(channel.role.color)
					}
				}
			}
		} header: {
			Text("Colour")
		} footer: {
			if programmer.macroOverridesMix {
				Text("This light is showing a built-in colour, so the mixer is doing nothing.")
			} else if programmer.isSubtractive {
				Text("This head makes colour by putting filters in front of a white lamp, so the dimmer sets how bright it is.")
			}
		}
		.task(id: programmer.title) {
			kelvin = programmer.kelvin
		}
	}
}
