import SwiftUI

struct FixtureTypeView: View {
	@Environment(FixtureLibrary.self) private var library
	
	let type: FixtureType
	
	var patching: Binding<Bool>?
	
	@State private var isEditing = false
	@State private var isPatching = false
	@ScaledMetric(relativeTo: .body) private var addressWidth = 58
	@ScaledMetric(relativeTo: .subheadline) private var rangeWidth = 68
	
	var body: some View {
		let type = library.type(self.type.id) ?? self.type
		
		List {
			if patching != nil {
				Section {
					Button("Use This Fixture") {
						isPatching = true
					}
					.font(.headline)
					.buttonStyle(.glassProminent)
					.controlSize(.large)
					.frame(maxWidth: .infinity)
				}
				.listRowBackground(Color.clear)
				.listRowInsets(.init(top: 0, leading: 20, bottom: 4, trailing: 20))
			}
			
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
			
			ForEach(type.channels) { channel in
				Section {
					ChannelDetail(channel: channel, addressWidth: addressWidth, rangeWidth: rangeWidth)
				}
			}
		}
		.listSectionSpacing(.compact)
		.contentMargins(.top, patching == nil ? 20 : 8, for: .scrollContent)
		.navigationDestination(isPresented: $isPatching) {
			if let patching {
				PatchView(mode: type, isPresented: patching)
			}
		}
		.navigationTitle(type.model)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			Button("Edit") { isEditing = true }
		}
		.sheet(isPresented: $isEditing) {
			FixtureTypeEditor(type: type)
				.id(type.id)
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
				.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
		} else {
			DisclosureGroup {
				if let dependency = channel.enabledBy {
					RangeRow(from: dependency.from, to: dependency.to, label: "Only while channel \(dependency.offset) reads this", width: rangeWidth, indent: 0)
				}
				
				ForEach(channel.functions) { function in
					RangeRow(from: function.from, to: function.to, label: function.label, swatch: function.swatch, hidesSeparator: !function.sets.isEmpty, width: rangeWidth, indent: 0)
					
					ForEach(function.sets) { set in
						RangeRow(from: set.from, to: set.to, label: set.label, swatch: set.swatch, isNested: true, hidesSeparator: set.id != function.sets.last?.id, width: rangeWidth, indent: 24)
					}
				}
			} label: {
				heading
			}
			.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
		}
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
