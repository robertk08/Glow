import SwiftUI

struct ProgrammerView: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.horizontalSizeClass) private var sizeClass
	
	let programmer: Programmer
	
	@State private var group = FeatureGroup.dimmer
	@State private var isShowingChannels = false
	
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
					ForEach(programmer.channels(in: .dimmer).filter { $0.attribute != .dimmer }) { channel in
						Section(channel.name) {
							ChannelRow(programmer: programmer, channel: channel)
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
					Button("Highlight", systemImage: "flashlight.on.fill") {
						programmer.highlight()
					}
					
					if programmer.isActive(group) {
						Button("Release \(group.name)", systemImage: "arrow.uturn.backward", role: .destructive) {
							programmer.release(group)
						}
					}
					
					if programmer.mode != nil {
						Button("All Channels", systemImage: "slider.horizontal.below.square.filled.and.square") {
							isShowingChannels = true
						}
					}
				} footer: {
					Text(programmer.mode == nil ? "Channels are shown when every selected light is the same fixture in the same mode." : "Highlight opens the fixture so you can find it on stage without changing anything you have set.")
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
			.navigationDestination(isPresented: $isShowingChannels) {
				ChannelsView(programmer: programmer)
			}
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
		VStack(spacing: 14) {
			LevelPad(level: programmer.brightnessBinding, glow: programmer.glow, isActive: programmer.isActive(.dimmer))
			
			HStack(spacing: 10) {
				Button("Off") { programmer.brightness = 0 }
				Button("25%") { programmer.brightness = 0.25 }
				Button("50%") { programmer.brightness = 0.5 }
				Button("75%") { programmer.brightness = 0.75 }
				Button("Full") { programmer.brightness = 1 }
			}
			.buttonStyle(.glass)
			.buttonBorderShape(.capsule)
			.controlSize(.small)
			.frame(maxWidth: .infinity)
		}
	}
}

private struct ColorPane: View {
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

private struct PositionPane: View {
	let programmer: Programmer
	
	var body: some View {
		VStack(spacing: 12) {
			PositionPad(pan: programmer.fractionBinding(.pan), tilt: programmer.fractionBinding(.tilt), panDegrees: programmer.mode?.panDegrees, tiltDegrees: programmer.mode?.tiltDegrees, isActive: programmer.isActive(.position))
			
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
				
				TemperatureStrip(kelvin: Binding { programmer.kelvin } set: { programmer.apply(kelvin: $0) })
			}
		}
		
		if let macro = programmer.macroChannel {
			Section(macro.name) {
				SlotPicker(programmer: programmer, channel: macro)
			}
		}
		
		ForEach(programmer.channels(in: .color).filter { !$0.attribute.isEmitter && $0.offset != programmer.macroChannel?.offset }) { channel in
			Section(channel.name) {
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
								.foregroundStyle(programmer.isActive(channel) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
						}
						.font(.subheadline)
						
						Slider(value: programmer.binding(channel), in: 0...255, neutralValue: Double(channel.defaultValue)) {
							Text(channel.name)
						}
						.tint(channel.attribute.color)
					}
				}
			}
		} footer: {
			if programmer.isSubtractive {
				Text("This head makes color by putting filters in front of a white lamp, so the dimmer sets how bright it is.")
			}
		}
	}
}

private struct PositionRows: View {
	let programmer: Programmer
	
	var body: some View {
		ForEach(programmer.channels(in: .position).filter { $0.attribute != .pan && $0.attribute != .tilt }) { channel in
			Section(channel.name) {
				ChannelRow(programmer: programmer, channel: channel)
			}
		}
	}
}

private struct BeamRows: View {
	let programmer: Programmer
	
	var body: some View {
		let shown = [programmer.channel(.zoom)?.offset, programmer.shutterChannel?.offset]
		
		ForEach(programmer.channels(in: .beam).filter { !shown.contains($0.offset) }) { channel in
			Section(channel.name) {
				ChannelRow(programmer: programmer, channel: channel)
			}
		}
	}
}

private struct WheelRows: View {
	let programmer: Programmer
	let group: FeatureGroup
	
	var body: some View {
		ForEach(programmer.channels(in: group)) { channel in
			Section {
				if channel.isBanded {
					SlotPicker(programmer: programmer, channel: channel)
				} else {
					ChannelRow(programmer: programmer, channel: channel)
				}
			} header: {
				HStack {
					Text(channel.name)
					
					if programmer.isActive(channel) {
						Image(systemName: "circle.fill")
							.font(.system(size: 6))
							.foregroundStyle(.tint)
							.accessibilityLabel("Set")
					}
				}
			}
		}
	}
}
