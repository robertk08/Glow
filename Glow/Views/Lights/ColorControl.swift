import SwiftUI

struct ColorControl: View {
	let control: FixtureControl
	
	@State private var kelvin: Double = ColorTemperature.neutral
	@State private var showsEmitters = false
	
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
						Haptic.feedback(.selection)
						control.apply(preset.mix(with: emitters))
					} label: {
						Circle()
							.fill(preset.swatch(with: emitters).color)
							.frame(height: 44)
							.overlay {
								Circle().strokeBorder(.separator)
							}
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.vertical, 4)
			
			Slider(value: control.hueBinding, in: 0...1) {
				Text("Hue")
			}
			
			Slider(value: control.saturationBinding, in: 0...1) {
				Text("Saturation")
			} minimumValueLabel: {
				Image(systemName: "circle")
			} maximumValueLabel: {
				Image(systemName: "circle.fill")
			}
			
			if canBalanceWhite {
				Slider(
					value: $kelvin,
					in: ColorTemperature.range,
					label: { Text("White balance") },
					minimumValueLabel: { Image(systemName: "thermometer.sun") },
					maximumValueLabel: { Image(systemName: "thermometer.snowflake") },
					ticks: {}
				)
				.onChange(of: balancedKelvin) {
					control.apply(.white(kelvin: balancedKelvin, with: emitters))
				}
				
				LabeledContent("Temperature", value: "\(Int(balancedKelvin)) K")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			
			DisclosureGroup("Emitters", isExpanded: $showsEmitters) {
				ForEach(control.profile.emitterChannels) { channel in
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
	
	// A slider given a `step` draws a tick for every one of them, and 50 K across
	// this range is 161 ticks — a solid grey smear under the track. So the slider
	// runs continuously and the grain moves here instead: the light and the
	// readout still only ever see round 50 K values.
	private var balancedKelvin: Double {
		(kelvin / Self.kelvinGrain).rounded() * Self.kelvinGrain
	}
	
	private static let kelvinGrain: Double = 50
	
	private var canBalanceWhite: Bool {
		emitters.contains(.white) || emitters.contains(.amber)
	}
}
