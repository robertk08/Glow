import SwiftUI

struct FixtureTypeRow: View {
	let type: FixtureType
	
	var body: some View {
		let modes = type.fixtureModes
		
		return Label {
			VStack(alignment: .leading, spacing: 2) {
				Text(type.name)
				
				Text((modes.first?.abilities ?? []).formatted(.list(type: .and)))
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			}
		} icon: {
			Image(systemName: type.symbol)
		}
		.badge(modes.count > 1 ? "^[\(modes.count) mode](inflect: true)" : "\(modes.first?.channelCount ?? 0) ch")
	}
}
