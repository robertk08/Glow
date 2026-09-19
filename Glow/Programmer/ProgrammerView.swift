import SwiftUI

struct ProgrammerView: View {
	@Environment(Console.self) private var console
	@Environment(\.dismiss) private var dismiss
	@Environment(\.horizontalSizeClass) private var sizeClass
	
	let programmer: Programmer
	
	var body: some View {
		NavigationStack {
			Form {
				if programmer.dims {
					Section("Intensity") {
						LabeledContent("Level", value: programmer.brightness, format: .percent.precision(.fractionLength(0)))
							.monospacedDigit()
						
						Slider(value: programmer.brightnessBinding, in: 0...1) {
							Text("Brightness")
						}
						.controlSize(.large)
					}
				}
				
				if programmer.mixesColor {
					ColorControl(programmer: programmer)
				}
				
				if programmer.movesHead {
					Section("Position") {
						PositionPad(pan: programmer.fractionBinding(.pan), tilt: programmer.fractionBinding(.tilt))
						
						VStack(alignment: .leading) {
							Text("Pan")
							Slider(value: programmer.fractionBinding(.pan), in: 0...1, neutralValue: 0.5) {
								Text("Pan")
							}
						}
						
						VStack(alignment: .leading) {
							Text("Tilt")
							Slider(value: programmer.fractionBinding(.tilt), in: 0...1, neutralValue: 0.5) {
								Text("Tilt")
							}
						}
						
						if let speed = programmer.profile?.channel(.movementSpeed) {
							VStack(alignment: .leading) {
								Text(speed.name)
								Slider(value: programmer.binding(speed), in: 0...255, neutralValue: Double(speed.defaultValue)) {
									Text(speed.name)
								}
							}
						}
						
						Button("Centre") {
							programmer.centre()
						}
					}
				}
				
				ForEach(programmer.settings) { channel in
					Section(channel.name) {
						if programmer.bands(of: channel).count > 1 {
							BandPicker(programmer: programmer, channel: channel, bands: programmer.bands(of: channel))
								.labelsHidden()
						}
						
						if let active = programmer.adjustableBand(of: channel) {
							Slider(value: programmer.binding(channel), in: Double(active.from)...Double(active.to))
						} else if channel.ranges.isEmpty {
							Slider(value: programmer.binding(channel), in: 0...255, neutralValue: Double(channel.defaultValue)) {
								Text(channel.name)
							}
						}
					}
				}
				
				Section {
					if programmer.profile == nil {
						LabeledContent("Fixtures", value: "Mixed")
					} else {
						NavigationLink("All Channels") {
							ChannelsView(programmer: programmer)
						}
					}
				} footer: {
					Text(programmer.profile == nil ? "Channels are shown when every selected light is the same fixture." : "Every channel the fixture has, on its raw DMX value.")
				}
				
				Section {
					Button("Reset to Defaults") {
						programmer.applyDefaults()
					}
				}
				
				Section("Master") {
					MasterBar()
						.listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
				}
			}
			.navigationTitle(programmer.title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				if sizeClass == .compact {
					ToolbarItem(placement: .topBarLeading) {
						ClearButton()
					}
					
					ToolbarItem(placement: .confirmationAction) {
						Button(role: .close) { dismiss() }
					}
				}
			}
		}
	}
}
