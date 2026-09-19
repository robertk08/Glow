import SwiftUI

struct FixtureTypeRow: View {
	let type: FixtureType
	
	var body: some View {
		Label {
			VStack(alignment: .leading, spacing: 2) {
				Text(type.name)
				
				Text(type.abilities.formatted(.list(type: .and)))
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			}
		} icon: {
			Image(systemName: type.symbol)
		}
		.badge(type.modes.count > 1 ? Text("^[\(type.modes.count) mode](inflect: true)") : Text(type.channelSpan))
	}
}
