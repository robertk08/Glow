import SwiftUI

struct IntensityPane: View {
	let programmer: Programmer
	
	var body: some View {
		VStack(spacing: 14) {
			LevelPad(level: programmer.brightnessBinding, glow: programmer.glow, isActive: programmer.isActive(.dimmer))
			
			HStack(spacing: 10) {
				Button("Off") { programmer.brightness = 0 }
				Button("25%") { programmer.brightness = 0.25 }
				Button("50%") { programmer.brightness = 0.5 }
				Button("75%") { programmer.brightness = 0.75 }
				Button("Full") { programmer.brightness = 1 }
			}
			.buttonStyle(.glass)
			.buttonBorderShape(.capsule)
			.controlSize(.small)
			.frame(maxWidth: .infinity)
		}
	}
}
