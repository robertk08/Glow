import SwiftUI

struct FixtureTypeView: View {
	@Environment(FixtureLibrary.self) private var library
	
	let type: FixtureType
	
	var patching: Binding<Bool>?
	
	@State private var isEditing = false
	
	var body: some View {
		let type = library.type(self.type.id) ?? self.type
		
		List {
			Section {
				if !type.manufacturer.isEmpty {
					LabeledContent("Make", value: type.manufacturer)
				}
				
				LabeledContent("Model", value: type.model)
				
				if !type.mode.isEmpty {
					LabeledContent("Mode", value: type.mode)
				}
				
				LabeledContent("Channels", value: "\(type.channelCount)")
				
				if type.mixesColor {
					LabeledContent("Color", value: type.mixing == .subtractive ? "CMY filters" : "Emitters")
				}
				
				if let pan = type.panDegrees {
					LabeledContent("Pan", value: "\(pan.formatted(.number.precision(.fractionLength(0))))°")
				}
				
				if let tilt = type.tiltDegrees {
					LabeledContent("Tilt", value: "\(tilt.formatted(.number.precision(.fractionLength(0))))°")
				}
			}
			
			if let patching {
				Section {
					NavigationLink("Add to the Patch") {
						PatchView(mode: type, isPresented: patching)
					}
				}
			}
			
			ForEach(type.channels) { channel in
				Section {
					ForEach(channel.functions) { function in
						LabeledContent {
							Text(function.label)
								.multilineTextAlignment(.trailing)
						} label: {
							HStack(spacing: 6) {
								if !function.swatch.isEmpty {
									Swatch(colors: function.swatch, size: 14)
								}
								
								Text("\(function.from)–\(function.to)")
									.monospacedDigit()
									.foregroundStyle(.secondary)
							}
						}
						.font(.caption)
						
						ForEach(function.sets) { set in
							LabeledContent {
								Text(set.label)
									.multilineTextAlignment(.trailing)
							} label: {
								HStack(spacing: 6) {
									if !set.swatch.isEmpty {
										Swatch(colors: set.swatch, size: 12)
									}
									
									Text("\(set.from)–\(set.to)")
										.monospacedDigit()
										.foregroundStyle(.secondary)
								}
							}
							.font(.caption2)
							.padding(.leading, 12)
						}
					}
				} header: {
					HStack {
						Text("\(channel.addressLabel). \(channel.name)")
						Spacer()
						Text("Default \(channel.defaultValue)")
							.monospacedDigit()
					}
				}
			}
		}
		.navigationTitle(type.model)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			Button("Edit") { isEditing = true }
		}
		.sheet(isPresented: $isEditing) {
			FixtureTypeEditor(type: type)
				.id(type)
		}
	}
}
