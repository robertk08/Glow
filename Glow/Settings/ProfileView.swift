import SwiftUI

struct ProfileView: View {
	@Environment(FixtureLibrary.self) private var library
	@State private var isEditing = false
	let profile: FixtureProfile
	
	var body: some View {
		let profile = library.profile(profile.id) ?? profile
		List {
			Section {
				if !profile.manufacturer.isEmpty {
					LabeledContent("Make", value: profile.manufacturer)
				}
				
				LabeledContent("Model", value: profile.model)
				
				if !profile.mode.isEmpty {
					LabeledContent("Mode", value: profile.mode)
				}
				
				LabeledContent("Channels", value: "\(profile.channelCount)")
				
				if profile.mixesColor {
					LabeledContent("Color", value: profile.mixing == .subtractive ? "CMY filters" : "Emitters")
				}
				
				if let pan = profile.panDegrees {
					LabeledContent("Pan", value: "\(pan.formatted(.number.precision(.fractionLength(0))))°")
				}
				
				if let tilt = profile.tiltDegrees {
					LabeledContent("Tilt", value: "\(tilt.formatted(.number.precision(.fractionLength(0))))°")
				}
			}
			
			ForEach(profile.channels) { channel in
				Section {
					ForEach(channel.ranges) { range in
						LabeledContent {
							Text(range.label)
								.multilineTextAlignment(.trailing)
						} label: {
							Text("\(range.from)–\(range.to)")
								.monospacedDigit()
								.foregroundStyle(.secondary)
						}
						.font(.caption)
					}
				} header: {
					HStack {
						Text("\(channel.offset). \(channel.name)")
						Spacer()
						Text("Default \(channel.defaultValue)")
							.monospacedDigit()
					}
				}
			}
		}
		.navigationTitle(profile.model)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			Button("Edit") { isEditing = true }
		}
		.sheet(isPresented: $isEditing) {
			CustomFixtureView(profile: profile)
				.id(profile)
		}
	}
}
