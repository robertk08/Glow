import SwiftUI

struct PositionPane: View {
	let programmer: Programmer
	
	var body: some View {
		VStack(spacing: 12) {
			PositionPad(pan: programmer.fractionBinding(.pan), tilt: programmer.fractionBinding(.tilt), panDegrees: programmer.mode?.panDegrees, tiltDegrees: programmer.mode?.tiltDegrees, isActive: programmer.isActive(.position))
			
			HStack(spacing: 10) {
				Button("Centre", systemImage: "scope") { programmer.centre() }
				Button("Home", systemImage: "house") { programmer.release(.position) }
			}
			.buttonStyle(.glass)
			.buttonBorderShape(.capsule)
			.controlSize(.small)
			.frame(maxWidth: .infinity)
		}
	}
}
