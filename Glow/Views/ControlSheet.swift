import SwiftUI

struct ControlSheet: View {
	@Environment(Console.self) private var console
	@Environment(\.dismiss) private var dismiss
	@Environment(\.horizontalSizeClass) private var sizeClass
	
	let control: FixtureControl
	
	@State private var confirmingRange: ChannelRange?
	@State private var confirmingChannel: ProfileChannel?
	
	var body: some View {
		NavigationStack {
			Form {
				if control.dims {
					Section("Brightness") {
						LabeledContent("Level", value: control.brightness, format: .percent.precision(.fractionLength(0)))
							.monospacedDigit()
						
						Slider(value: control.brightnessBinding, in: 0...1) {
							Text("Brightness")
						}
						.controlSize(.large)
					}
				}
				
				if control.mixesColor {
					ColorControl(control: control)
				}
				
				if control.movesHead {
					Section("Position") {
						PositionPad(pan: control.fractionBinding(.pan), tilt: control.fractionBinding(.tilt))
						
						VStack(alignment: .leading) {
							Text("Pan")
							Slider(value: control.fractionBinding(.pan))
						}
						
						VStack(alignment: .leading) {
							Text("Tilt")
							Slider(value: control.fractionBinding(.tilt))
						}
						
						if let speed = control.profile?.channel(.movementSpeed) {
							VStack(alignment: .leading) {
								Text(speed.name)
								Slider(value: control.binding(speed), in: 0...255)
							}
						}
						
						Button("Centre") {
							control.centre()
						}
					}
				}
				
				ForEach(control.settings) { channel in
					Section(channel.name) {
						if control.bands(of: channel).count > 1 {
							Picker(channel.name, selection: Binding { control.band(of: channel)?.id ?? "" } set: { id in
								guard let range = channel.ranges.first(where: { $0.id == id }) else { return }
								
								if range.requiresConfirmation {
									confirmingRange = range
									confirmingChannel = channel
								} else {
									control.set(range.midpoint, of: channel)
								}
							}) {
								ForEach(control.bands(of: channel)) { range in
									Text(range.label).tag(range.id)
								}
							}
							.labelsHidden()
						}
						
						if let active = control.adjustableBand(of: channel) {
							Slider(value: control.binding(channel), in: Double(active.from)...Double(active.to))
						} else if channel.ranges.isEmpty {
							Slider(value: control.binding(channel), in: 0...255)
						}
					}
				}
				
				Section {
					Button("Bring Up") {
						control.home()
					}
					
					Button("Reset to Defaults") {
						control.applyDefaults()
					}
					
					if control.isSingle {
						NavigationLink("All Channels") {
							ChannelsView(control: control)
						}
					}
				} footer: {
					Text("Bring Up centres the head, opens it and goes to white. Reset puts every channel back where the fixture profile says it starts.")
				}
			}
			.navigationTitle(control.title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Clear") {
						console.selection.removeAll()
					}
				}
				
				if sizeClass == .compact {
					ToolbarItem(placement: .confirmationAction) {
						Button("Done") {
							dismiss()
						}
					}
				}
			}
			.alert(confirmingRange?.label ?? "", isPresented: Binding { confirmingRange != nil } set: { _ in confirmingRange = nil }) {
				Button("Cancel", role: .cancel) {
					confirmingRange = nil
					confirmingChannel = nil
				}
				
				Button("Send", role: .destructive) {
					if let confirmingRange, let confirmingChannel {
						control.set(confirmingRange.midpoint, of: confirmingChannel)
					}
					
					confirmingRange = nil
					confirmingChannel = nil
				}
			} message: {
				Text("The light stops responding for a few seconds.")
			}
		}
	}
}
