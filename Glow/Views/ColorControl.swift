import SwiftUI

struct ColorControl: View {
	let control: SelectionControl
	
	@State private var kelvin: Double = ColorTemperature.neutral
	@State private var showsEmitters = false
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
	
	private var balancesWhite: Bool {
		control.emitters.contains(.white) || control.emitters.contains(.amber)
	}
	
	var body: some View {
		Section {
			if control.macroOverridesMix {
				Button("Use the colour mixer") {
					control.releaseMix()
				}
			}
			
			ColorPicker("Any colour", selection: control.colorBinding, supportsOpacity: false)
			
			LazyVGrid(columns: columns, spacing: 12) {
				ForEach(control.presets) { preset in
					Button {
						control.apply(preset)
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
			
			if balancesWhite {
				VStack(alignment: .leading) {
					LabeledContent("White balance", value: "\(Int(kelvin)) K")
					
					Slider(value: $kelvin, in: ColorTemperature.range, step: 50) {
						Text("White balance")
					} minimumValueLabel: {
						Image(systemName: "thermometer.sun")
					} maximumValueLabel: {
						Image(systemName: "thermometer.snowflake")
					}
					.onChange(of: kelvin) {
						control.apply(kelvin: kelvin)
					}
				}
			}
			
			DisclosureGroup("Emitters", isExpanded: $showsEmitters) {
				ForEach(control.emitterChannels) { channel in
					VStack(alignment: .leading, spacing: 6) {
						LabeledContent(channel.name) {
							Text("\(control.value(of: channel))")
								.monospacedDigit()
								.foregroundStyle(.secondary)
						}
						.font(.subheadline)
						
						Slider(value: control.binding(channel), in: 0...255, step: 1)
							.tint(channel.role.color)
					}
				}
			}
		} header: {
			Text("Colour")
		} footer: {
			if control.macroOverridesMix {
				Text("This light is showing a built-in colour, so the mixer is doing nothing.")
			}
		}
		.task {
			kelvin = control.kelvin
		}
	}
}
