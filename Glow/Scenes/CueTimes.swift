import SwiftUI

struct CueTimes: View {
	let cue: Cue
	
	var body: some View {
		HStack(spacing: 10) {
			ForEach(cue.times, id: \.time) { entry in
				HStack(spacing: 3) {
					Image(systemName: entry.time.symbol)
						.imageScale(.small)
					
					Text(Cue.seconds(entry.seconds))
				}
				.accessibilityElement(children: .ignore)
				.accessibilityLabel("\(entry.time.name) \(Cue.seconds(entry.seconds))")
			}
		}
		.monospacedDigit()
	}
}
