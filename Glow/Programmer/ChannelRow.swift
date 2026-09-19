import SwiftUI

struct ChannelRow: View {
	let programmer: Programmer
	let channel: FixtureChannel
	
	var body: some View {
		let blocker = programmer.blocker(of: channel)
		
		Group {
			LabeledContent {
				Text(programmer.physical(of: channel) ?? programmer.bandLabel(of: channel))
					.monospacedDigit()
					.foregroundStyle(programmer.isActive(channel) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
					.lineLimit(1)
			} label: {
				Label(channel.name, systemImage: channel.attribute.symbol)
					.labelStyle(.titleOnly)
			}
			.font(.subheadline)
			
			if channel.functions.count > 1 {
				SlotPicker(programmer: programmer, channel: channel)
			} else {
				Slider(value: programmer.binding(channel), in: 0...255, neutralValue: Double(channel.defaultValue)) {
					Text(channel.name)
				}
				.tint(channel.attribute.color)
			}
		}
		.disabled(blocker != nil)
		.opacity(blocker == nil ? 1 : 0.45)
		.overlay(alignment: .bottomLeading) {
			if let blocker {
				Text("\(blocker.name) has this channel switched off.")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}
}
