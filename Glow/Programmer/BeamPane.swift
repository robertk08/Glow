import SwiftUI

struct BeamPane: View {
	let programmer: Programmer
	
	var body: some View {
		let shutter = programmer.shutterChannel
		
		VStack(spacing: 12) {
			if programmer.channel(.zoom) != nil {
				BeamPad(zoom: programmer.fractionBinding(.zoom), focus: programmer.fractionBinding(.focus), glow: programmer.glow, degrees: programmer.degrees(.zoom), hasFocus: programmer.channel(.focus) != nil)
			}
			
			if let shutter, shutter.functions.contains(where: { $0.unit == .hertz }) {
				StrobePad(rate: programmer.fractionBinding(of: shutter), glow: programmer.glow, hertz: programmer.strobeHertz, isRunning: programmer.strobeHertz != nil)
			}
		}
	}
}
