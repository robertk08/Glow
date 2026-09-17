import SwiftUI

struct ProfileView: View {
	let profile: FixtureProfile
	
	var body: some View {
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
					LabeledContent("Colour", value: profile.mixing == .subtractive ? "CMY filters" : "Emitters")
				}
				
				if let pan = profile.panDegrees {
					LabeledContent("Pan", value: "\(Int(pan))°")
				}
				
				if let tilt = profile.tiltDegrees {
					LabeledContent("Tilt", value: "\(Int(tilt))°")
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
						if channel.defaultValue != 0 {
							Text("starts at \(channel.defaultValue)")
								.monospacedDigit()
						}
					}
				}
			}
		}
		.navigationTitle(profile.model)
		.navigationBarTitleDisplayMode(.inline)
	}
}
