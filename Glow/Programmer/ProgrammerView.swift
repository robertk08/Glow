import SwiftUI

struct ProgrammerView: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.horizontalSizeClass) private var sizeClass
	
	let programmer: Programmer
	
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
				}
				
				switch group {
				case .dimmer:
					if !programmer.channels(in: .dimmer).filter({ $0.attribute != .dimmer }).isEmpty {
						Section {
							ForEach(programmer.channels(in: .dimmer).filter { $0.attribute != .dimmer }) { channel in
								ChannelRow(programmer: programmer, channel: channel)
							}
						}
					}
				case .color:
					ColorRows(programmer: programmer)
				case .position:
					PositionRows(programmer: programmer)
				case .gobo:
					WheelRows(programmer: programmer, group: .gobo)
				case .beam:
					BeamRows(programmer: programmer)
				case .control:
					WheelRows(programmer: programmer, group: .control)
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
			.safeAreaInset(edge: .top, spacing: 0) {
				VStack(spacing: 10) {
					FeatureGroupPicker(programmer: programmer, group: $group)
					
					Group {
						switch group {
						case .dimmer where programmer.dims: IntensityPane(programmer: programmer)
						case .color where programmer.mixesColor: ColorPane(programmer: programmer)
						case .position where programmer.movesHead: PositionPane(programmer: programmer)
						case .beam where programmer.hasBeamShape: BeamPane(programmer: programmer)
						default: EmptyView()
						}
					}
					.padding(.horizontal)
					.padding(.bottom, 10)
				}
				.background(.bar)
			}
			.navigationTitle(programmer.title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					ClearButton()
				}
				
				if sizeClass == .compact {
					ToolbarItem(placement: .confirmationAction) {
						Button(role: .close) { dismiss() }
					}
				}
			}
		}
	}
}

private struct IntensityPane: View {
	let programmer: Programmer
	
	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			LabeledContent("Level", value: programmer.brightness, format: .percent.precision(.fractionLength(0)))
				.font(.subheadline)
				.monospacedDigit()
			
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

private struct ColorPane: View {
	let programmer: Programmer
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]
	
	var body: some View {
		VStack(spacing: 12) {
			ColorPicker("Color", selection: programmer.colorBinding, supportsOpacity: false)
			
			LazyVGrid(columns: columns, spacing: 10) {
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
		}
	}
}

private struct PositionPane: View {
	let programmer: Programmer
	
	var body: some View {
		VStack(spacing: 12) {
			PositionPad(pan: programmer.fractionBinding(.pan), tilt: programmer.fractionBinding(.tilt), panDegrees: programmer.type?.panDegrees, tiltDegrees: programmer.type?.tiltDegrees, isActive: programmer.isActive(.position))
			
			HStack(spacing: 10) {
				Button("Centre", systemImage: "scope") { programmer.centre() }
				Button("Home", systemImage: "house") { programmer.release(.position) }
			}
			.buttonStyle(.glass)
			.buttonBorderShape(.capsule)
			.controlSize(.small)
			.frame(maxWidth: .infinity)
		}
	}
}

private struct BeamPane: View {
	let programmer: Programmer
	
	var body: some View {
		let shutter = programmer.shutterChannel
		
		VStack(spacing: 12) {
			if programmer.channel(.zoom) != nil {
				BeamPad(zoom: programmer.fractionBinding(.zoom), focus: programmer.fractionBinding(.focus), glow: programmer.glow, degrees: programmer.degrees(.zoom), hasFocus: programmer.channel(.focus) != nil)
			}
			
			if let shutter, shutter.functions.contains(where: { $0.unit == .hertz }) {
				StrobePad(rate: programmer.fractionBinding(of: shutter), glow: programmer.glow, hertz: programmer.strobeHertz, isRunning: programmer.strobeHertz != nil)
			}
		}
	}
}

private struct ColorRows: View {
	let programmer: Programmer
	
	@State private var showsEmitters = false
	
	var body: some View {
		if programmer.balancesWhite {
			Section {
				LabeledContent("White balance", value: "\(Int(programmer.kelvin)) K")
					.font(.subheadline)
					.monospacedDigit()
				
				Slider(value: Binding { programmer.kelvin } set: { programmer.apply(kelvin: $0) }, in: ColorTemperature.range, neutralValue: ColorTemperature.neutral) {
					Text("White balance")
				} minimumValueLabel: {
					Image(systemName: "thermometer.sun")
				} maximumValueLabel: {
					Image(systemName: "thermometer.snowflake")
				}
			}
		}
		
		if let macro = programmer.macroChannel {
			Section {
				SlotPicker(programmer: programmer, channel: macro)
			}
		}
		
		Section {
			ForEach(programmer.channels(in: .color).filter { !$0.attribute.isEmitter && $0.offset != programmer.macroChannel?.offset }) { channel in
				ChannelRow(programmer: programmer, channel: channel)
			}
		}
		
		Section {
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
						.tint(channel.attribute.color)
					}
				}
			}
		}
	}
}

private struct PositionRows: View {
	let programmer: Programmer
	
	var body: some View {
		Section {
			ForEach(programmer.channels(in: .position).filter { $0.attribute != .pan && $0.attribute != .tilt }) { channel in
				ChannelRow(programmer: programmer, channel: channel)
			}
		}
	}
}

private struct BeamRows: View {
	let programmer: Programmer
	
	var body: some View {
		let shown = [programmer.channel(.zoom)?.offset, programmer.shutterChannel?.offset]
		
		Section {
			ForEach(programmer.channels(in: .beam).filter { !shown.contains($0.offset) }) { channel in
				ChannelRow(programmer: programmer, channel: channel)
			}
		}
	}
}

private struct WheelRows: View {
	let programmer: Programmer
	let group: FeatureGroup
	
	var body: some View {
		Section {
			ForEach(programmer.channels(in: group)) { channel in
				ChannelRow(programmer: programmer, channel: channel)
			}
		}
	}
}
