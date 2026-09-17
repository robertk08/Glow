import SwiftUI

struct ProfileRow: View {
	let profile: FixtureProfile
	
	var body: some View {
		Label {
			VStack(alignment: .leading) {
				Text(profile.name)
				Text(profile.mode)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		} icon: {
			Image(systemName: profile.symbol)
		}
	}
}
