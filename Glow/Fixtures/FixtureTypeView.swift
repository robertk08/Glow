import SwiftUI

struct FixtureTypeView: View {
	@Environment(FixtureLibrary.self) private var library
	
	let type: FixtureType
	
	var patching: Binding<Bool>?
	
	@State private var isEditing = false
	@ScaledMetric(relativeTo: .body) private var addressWidth = 58
	@ScaledMetric(relativeTo: .subheadline) private var rangeWidth = 64
	
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
					.monospacedDigit()
				
				if type.mixesColor {
					LabeledContent("Color", value: type.mixing == .subtractive ? "CMY filters" : "Emitters")
				}
				
				if let pan = type.panDegrees {
					LabeledContent("Pan", value: "\(pan.formatted(.number.precision(.fractionLength(0))))°")
						.monospacedDigit()
				}
				
				if let tilt = type.tiltDegrees {
					LabeledContent("Tilt", value: "\(tilt.formatted(.number.precision(.fractionLength(0))))°")
						.monospacedDigit()
				}
			}
			
			if let patching {
				Section {
					NavigationLink("Add to the Patch") {
						PatchView(mode: type, isPresented: patching)
					}
				}
			}
			
			ForEach(type.groups) { group in
				Section {
					ForEach(type.channels(in: group)) { channel in
						ChannelDetail(channel: channel, addressWidth: addressWidth, rangeWidth: rangeWidth)
					}
				} header: {
					Label(group.name, systemImage: group.symbol)
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

private struct ChannelDetail: View {
	let channel: FixtureChannel
	let addressWidth: CGFloat
	let rangeWidth: CGFloat
	
	private var heading: some View {
		HStack(alignment: .firstTextBaseline, spacing: 10) {
			Text(channel.addressLabel)
				.monospacedDigit()
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.frame(width: addressWidth, alignment: .trailing)
			
			VStack(alignment: .leading, spacing: 2) {
				Text(channel.name)
				
				Text(channel.summary)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}
	
	var body: some View {
		if channel.functions.isEmpty {
			heading
		} else {
			DisclosureGroup {
				if let dependency = channel.enabledBy {
					RangeRow(from: dependency.from, to: dependency.to, label: "Only while channel \(dependency.offset) reads", width: rangeWidth, indent: 0)
				}
				
				ForEach(channel.functions) { function in
					RangeRow(from: function.from, to: function.to, label: function.label, detail: function.physicalRange, swatch: function.swatch, width: rangeWidth, indent: 0)
					
					ForEach(function.sets) { set in
						RangeRow(from: set.from, to: set.to, label: set.label, swatch: set.swatch, width: rangeWidth, indent: 18)
					}
				}
			} label: {
				heading
			}
		}
	}
}

private struct RangeRow: View {
	let from: UInt8
	let to: UInt8
	let label: String
	
	var detail: String?
	var swatch: [LightColor] = []
	
	let width: CGFloat
	let indent: CGFloat
	
	var body: some View {
		LabeledContent {
			VStack(alignment: .trailing, spacing: 1) {
				Text(label)
					.multilineTextAlignment(.trailing)
				
				if let detail {
					Text(detail)
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			}
		} label: {
			HStack(spacing: 8) {
				Text("\(from)–\(to)")
					.monospacedDigit()
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.frame(width: width, alignment: .leading)
				
				if !swatch.isEmpty {
					Swatch(colors: swatch, size: 14)
				}
			}
			.padding(.leading, indent)
		}
		.font(.subheadline)
	}
}
