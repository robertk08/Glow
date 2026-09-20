import SwiftUI

struct FixtureTypeView: View {
	@Environment(FixtureLibrary.self) private var library
	
	let type: FixtureType
	
	var patching: Binding<Bool>?
	
	@State private var isEditing = false
	@ScaledMetric(relativeTo: .body) private var addressWidth = 58
	@ScaledMetric(relativeTo: .subheadline) private var rangeWidth = 68
	
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
			
			ForEach(type.channels) { channel in
				Section {
					if channel.functions.isEmpty {
						Text("No ranges")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
					
					if let dependency = channel.enabledBy {
						RangeRow(from: dependency.from, to: dependency.to, label: "Only while channel \(dependency.offset) reads this", width: rangeWidth, indent: 0)
					}
					
					ForEach(channel.functions) { function in
						RangeRow(from: function.from, to: function.to, label: function.label, swatch: function.swatch, hidesSeparator: !function.sets.isEmpty, width: rangeWidth, indent: 0)
						
						ForEach(function.sets) { set in
							RangeRow(from: set.from, to: set.to, label: set.label, swatch: set.swatch, isNested: true, hidesSeparator: set.id != function.sets.last?.id, width: rangeWidth, indent: 24)
						}
					}
				} header: {
					ChannelHeader(channel: channel, addressWidth: addressWidth)
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

private struct ChannelHeader: View {
	let channel: FixtureChannel
	let addressWidth: CGFloat
	
	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 10) {
			Text(channel.addressLabel)
				.monospacedDigit()
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.frame(width: addressWidth, alignment: .trailing)
			
			VStack(alignment: .leading, spacing: 2) {
				Text(channel.name)
					.font(.headline)
					.foregroundStyle(.primary)
				
				Text(channel.summary)
					.font(.caption)
			}
		}
		.textCase(nil)
		.padding(.bottom, 2)
	}
}

private struct RangeRow: View {
	let from: UInt8
	let to: UInt8
	let label: String
	
	var swatch: [LightColor] = []
	var isNested = false
	var hidesSeparator = false
	
	let width: CGFloat
	let indent: CGFloat
	
	var body: some View {
		HStack(spacing: 10) {
			Text("\(from)–\(to)")
				.monospacedDigit()
				.foregroundStyle(isNested ? HierarchicalShapeStyle.tertiary : .secondary)
				.lineLimit(1)
				.frame(width: width, alignment: .leading)
			
			Text(label)
				.foregroundStyle(isNested ? HierarchicalShapeStyle.secondary : .primary)
				.frame(maxWidth: .infinity, alignment: .leading)
			
			if !swatch.isEmpty {
				Swatch(colors: swatch, size: isNested ? 12 : 14)
			}
		}
		.font(isNested ? .footnote : .subheadline)
		.padding(.leading, indent)
		.alignmentGuide(.listRowSeparatorLeading) { _ in indent }
		.listRowSeparator(hidesSeparator ? .hidden : .automatic, edges: .bottom)
	}
}
