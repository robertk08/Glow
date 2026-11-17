import SwiftUI

struct ProgrammerView: View {
	@Environment(\.dismiss) private var dismiss
	
	let programmer: Programmer
	
	var isSheet = false
	
	@State private var group = FeatureGroup.dimmer
	
	var body: some View {
		let group = programmer.groups.contains(self.group) ? self.group : programmer.groups.first ?? .dimmer
		
		return NavigationStack {
			List {
				if programmer.groups.isEmpty {
					ContentUnavailableView {
						Label(programmer.targets.isEmpty ? "Nothing Selected" : "Nothing to Drive", systemImage: "lightbulb")
					} description: {
						Text(programmer.targets.isEmpty ? "Tap a light in the grid to take control of it." : "These lights have no channels Glow recognises.")
					}
					.listRowBackground(Color.clear)
					.listRowSeparator(.hidden)
				}
				
				switch group {
				case .dimmer: IntensityRows(programmer: programmer)
				case .color: ColorRows(programmer: programmer)
				case .position: PositionRows(programmer: programmer)
				case .gobo: GoboRows(programmer: programmer)
				case .beam: BeamRows(programmer: programmer)
				case .control: ChannelRows(programmer: programmer, channels: programmer.extras(on: .control))
				}
				
				Section {
					if programmer.type != nil {
						NavigationLink("All Channels") {
							ChannelsView(programmer: programmer)
						}
					}
					
					Button("Reset to Defaults") {
						programmer.applyDefaults()
					}
				}
			}
			.safeAreaBar(edge: .top) {
				FeatureGroupPicker(programmer: programmer, group: $group)
			}
			.safeAreaBar(edge: .bottom) {
				if !isSheet {
					MasterBar(isRaised: true)
						.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
				}
			}
			.navigationTitle(programmer.title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					ClearButton()
				}
				
				if isSheet {
					ToolbarItem(placement: .topBarTrailing) {
						Button(role: .close) { dismiss() }
					}
				}
			}
		}
	}
}

private struct IntensityRows: View {
	let programmer: Programmer
	
	var body: some View {
		if programmer.dims {
			Section("Level") {
				VStack(alignment: .leading, spacing: 4) {
					Text(programmer.brightness, format: .percent.precision(.fractionLength(0)))
						.font(.title.weight(.semibold))
						.monospacedDigit()
						.contentTransition(.numericText())
					
					Slider(value: programmer.brightnessBinding, in: 0...1) {
						Text("Brightness")
					} minimumValueLabel: {
						Image(systemName: "sun.min")
					} maximumValueLabel: {
						Image(systemName: "sun.max")
					}
					.controlSize(.large)
				}
			}
		}
		
		ChannelRows(programmer: programmer, channels: programmer.extras(on: .dimmer))
	}
}

private struct ColorRows: View {
	let programmer: Programmer
	
	@State private var showsEmitters = false
	@State private var picks = 0
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]
	
	var body: some View {
		if programmer.mixesColor {
			Section("Color") {
				ColorPicker("Color", selection: programmer.colorBinding, supportsOpacity: false)
				
				LazyVGrid(columns: columns, spacing: 10) {
					ForEach(programmer.presets) { preset in
						Button {
							picks += 1
							programmer.apply(preset)
						} label: {
							Swatch(colors: [preset.swatch], isSelected: programmer.selectedPresetID == preset.id)
						}
						.buttonStyle(.plain)
						.accessibilityLabel(preset.name)
					}
				}
				.padding(.vertical, 4)
				.sensoryFeedback(.selection, trigger: picks)
			}
		}
		
		if let temperature = programmer.temperatureChannel {
			Section("White Balance") {
				ChannelRow(programmer: programmer, channel: temperature)
			}
		} else if programmer.balancesWhite {
			Section("White Balance") {
				VStack(alignment: .leading, spacing: 4) {
					Text("\(Int(programmer.kelvin)) K")
						.font(.title3.weight(.semibold))
						.monospacedDigit()
						.contentTransition(.numericText())
					
					Slider(value: Binding { programmer.kelvin } set: { programmer.apply(kelvin: $0) }, in: ColorTemperature.range, neutralValue: ColorTemperature.neutral) {
						Text("White balance")
					} minimumValueLabel: {
						Image(systemName: "thermometer.sun")
					} maximumValueLabel: {
						Image(systemName: "thermometer.snowflake")
					}
				}
			}
		}
		
		if let macro = programmer.macroChannel {
			Section("Built-in Colors") {
				SlotPicker(programmer: programmer, channel: macro)
			}
		}
		
		ChannelRows(programmer: programmer, channels: programmer.extras(on: .color))
		
		if !programmer.emitterChannels.isEmpty {
			Section {
				DisclosureGroup(programmer.isSubtractive ? "Filters" : "Emitters", isExpanded: $showsEmitters) {
					ForEach(programmer.emitterChannels) { channel in
						VStack(alignment: .leading, spacing: 6) {
							LabeledContent(channel.name) {
								Text("\(programmer.value(of: channel))")
									.monospacedDigit()
									.foregroundStyle(.secondary)
									.contentTransition(.numericText())
							}
							.font(.subheadline)
							
							Slider(value: programmer.binding(channel), in: 0...255, neutralValue: Double(channel.defaultValue)) {
								Text(channel.name)
							}
							.tint(channel.attribute.color)
						}
					}
				}
			}
		}
	}
}

private struct PositionRows: View {
	@Environment(\.dynamicTypeSize) private var typeSize
	
	let programmer: Programmer
	
	@State private var showsAxes = false
	
	var body: some View {
		if programmer.movesHead {
			Section("Aim") {
				PositionPad(pan: programmer.fractionBinding(.pan), tilt: programmer.fractionBinding(.tilt), panDegrees: programmer.type?.panDegrees, tiltDegrees: programmer.type?.tiltDegrees)
					.listRowBackground(Color.clear)
					.listRowSeparator(.hidden)
					.listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
				
				let layout = typeSize >= .xxxLarge ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
				
				layout {
					Button("Centre", systemImage: "scope") { programmer.centre() }
					Button("Reset Position", systemImage: "arrow.uturn.backward") { programmer.release(.position) }
				}
				.buttonStyle(.glass)
				.buttonBorderShape(.capsule)
				.controlSize(.small)
				.frame(maxWidth: .infinity)
				.listRowBackground(Color.clear)
				.listRowSeparator(.hidden)
			}
		}
		
		Section {
			DisclosureGroup("Pan and Tilt", isExpanded: $showsAxes) {
				ForEach(programmer.axes) { attribute in
					VStack(alignment: .leading, spacing: 6) {
						LabeledContent(attribute.name) {
							Text(programmer.reading(attribute))
								.monospacedDigit()
								.foregroundStyle(.secondary)
								.contentTransition(.numericText())
						}
						
						Slider(value: programmer.fractionBinding(attribute), in: 0...1, neutralValue: 0.5) {
							Text(attribute.name)
						}
						.tint(attribute.color)
					}
				}
				
				ForEach(programmer.extras(on: .position)) { channel in
					ChannelRow(programmer: programmer, channel: channel)
				}
			}
		}
	}
}

private struct BeamRows: View {
	let programmer: Programmer
	
	var body: some View {
		let shutter = programmer.shutterChannel
		
		if programmer.channel(.zoom) != nil {
			Section("Beam") {
				BeamPad(zoom: programmer.fractionBinding(.zoom), focus: programmer.fractionBinding(.focus), glow: programmer.glow, degrees: programmer.degrees(.zoom), hasFocus: programmer.channel(.focus) != nil)
					.listRowBackground(Color.clear)
					.listRowSeparator(.hidden)
					.listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
			}
		}
		
		if let shutter {
			if shutter.functions.contains(where: { $0.unit == .hertz }) {
				Section("Shutter") {
					StrobePad(glow: programmer.glow, hertz: programmer.strobeHertz)
						.listRowBackground(Color.clear)
						.listRowSeparator(.hidden)
						.listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
				}
				
				Section {
					ChannelRow(programmer: programmer, channel: shutter)
				}
			} else {
				Section("Shutter") {
					ChannelRow(programmer: programmer, channel: shutter)
				}
			}
		}
		
		ChannelRows(programmer: programmer, channels: programmer.extras(on: .beam))
	}
}

private struct GoboRows: View {
	let programmer: Programmer
	
	var body: some View {
		ForEach(programmer.goboWheels) { wheel in
			if programmer.draws(wheel) {
				Section(wheel.name) {
					GoboPad(shape: programmer.shape(of: wheel), label: programmer.standing(of: wheel), tint: programmer.glow, angle: programmer.standingAngle(of: programmer.spinner(of: wheel)), turns: programmer.turns(of: programmer.spinner(of: wheel)))
						.listRowBackground(Color.clear)
						.listRowSeparator(.hidden)
						.listRowInsets(.init(top: 0, leading: 0, bottom: 4, trailing: 0))
				}
				
				Section {
					GoboWheelRows(programmer: programmer, wheel: wheel)
				}
			} else {
				Section(wheel.name) {
					GoboWheelRows(programmer: programmer, wheel: wheel)
				}
			}
		}
		
		ChannelRows(programmer: programmer, channels: programmer.extras(on: .gobo))
	}
}

private struct GoboWheelRows: View {
	let programmer: Programmer
	let wheel: FixtureChannel
	
	var body: some View {
		ChannelRow(programmer: programmer, channel: wheel)
		
		if let spinner = programmer.spinner(of: wheel) {
			ChannelRow(programmer: programmer, channel: spinner)
		}
	}
}

private struct ChannelRows: View {
	let programmer: Programmer
	let channels: [FixtureChannel]
	
	var body: some View {
		if !channels.isEmpty {
			Section {
				ForEach(channels) { channel in
					ChannelRow(programmer: programmer, channel: channel)
				}
			}
		}
	}
}
