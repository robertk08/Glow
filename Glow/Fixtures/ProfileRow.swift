import SwiftUI

struct ProfileRow: View {
	let profile: FixtureProfile
	
	var body: some View {
		Label {
			VStack(alignment: .leading, spacing: 2) {
				Text(profile.name)
				
				Text(profile.abilities.isEmpty ? profile.mode : "\(profile.mode) · \(profile.abilities.formatted(.list(type: .and)))")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			}
		} icon: {
			Image(systemName: profile.symbol)
		}
	}
}
