import SwiftUI

struct FixtureTypeRow: View {
	let type: FixtureType
	
	var body: some View {
		Label {
			VStack(alignment: .leading, spacing: 2) {
				Text(type.name)
				
				Text("^[\(type.channelCount) channel](inflect: true)")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			}
		} icon: {
			Image(systemName: type.symbol)
		}
	}
}
