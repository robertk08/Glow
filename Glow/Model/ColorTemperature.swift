import SwiftUI

nonisolated enum ColorTemperature {
	static let range: ClosedRange<Double> = 2000...10000
	
	static let warm: Double = 2700
	static let neutral: Double = 4000
	static let cool: Double = 6500
	
	static func light(kelvin: Double) -> LightColor {
		let t = min(max(kelvin, 1000), 40000) / 100
		
		let red: Double = t <= 66 ? 255 : 329.698_727_446 * pow(t - 60, -0.133_204_759_2)
		
		let green: Double =
			if t <= 66 { 99.470_802_586_1 * log(t) - 161.119_568_166_1 }
			else { 288.122_169_528_3 * pow(t - 60, -0.075_514_849_2) }
		
		let blue: Double =
			if t >= 66 { 255 }
			else if t <= 19 { 0 }
			else { 138.517_731_223_1 * log(t - 10) - 305.044_792_730_7 }
		
		return LightColor(red: red / 255, green: green / 255, blue: blue / 255).clamped.normalised
	}
	
	static func swatch(kelvin: Double) -> LightColor {
		let tint = light(kelvin: kelvin)
		return tint + (LightColor(red: 1, green: 1, blue: 1) - tint) * 0.55
	}
	
	static func nearest(to light: LightColor) -> Double? {
		let target = light.normalised
		var best = range.lowerBound
		var bestDistance = Double.infinity
		
		for kelvin in stride(from: range.lowerBound, through: range.upperBound, by: 50) {
			let distance = self.light(kelvin: kelvin).distance(to: target)
			if distance < bestDistance {
				bestDistance = distance
				best = kelvin
			}
		}
		
		guard bestDistance <= 0.045 else { return nil }
		return best
	}
}
