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
						case .dimmer: IntensityPane(programmer: programmer)
						case .color: ColorPane(programmer: programmer)
						case .position: PositionPane(programmer: programmer)
						case .beam: BeamPane(programmer: programmer)
						case .gobo, .control: EmptyView()
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
