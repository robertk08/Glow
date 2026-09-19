import SwiftUI

nonisolated struct LightColor: Hashable, Sendable {
	var red: Double
	var green: Double
	var blue: Double
	
	static let black = LightColor(red: 0, green: 0, blue: 0)
	
	init(red: Double, green: Double, blue: Double) {
		self.red = red
		self.green = green
		self.blue = blue
	}
	
	init?(hex: String) {
		let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
		var value: UInt64 = 0
		guard digits.count == 6, Scanner(string: digits).scanHexInt64(&value) else { return nil }
		self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
	}
	
	init(hue: Double, saturation: Double) {
		let h = (hue - hue.rounded(.down)) * 6
		let sector = Int(h)
		let f = h - Double(sector)
		let p = 1 - saturation
		let q = 1 - f * saturation
		let t = 1 - (1 - f) * saturation
		
		switch sector {
		case 0: self.init(red: 1, green: t, blue: p)
		case 1: self.init(red: q, green: 1, blue: p)
		case 2: self.init(red: p, green: 1, blue: t)
		case 3: self.init(red: p, green: q, blue: 1)
		case 4: self.init(red: t, green: p, blue: 1)
		default: self.init(red: 1, green: p, blue: q)
		}
	}
	
	@MainActor init(_ color: Color) {
		var red: CGFloat = 0
		var green: CGFloat = 0
		var blue: CGFloat = 0
		var alpha: CGFloat = 0
		UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		self.init(red: red, green: green, blue: blue)
	}
	
	var hex: String {
		let c = clamped
		return String(format: "%02x%02x%02x", Int((c.red * 255).rounded()), Int((c.green * 255).rounded()), Int((c.blue * 255).rounded()))
	}
	
	var peak: Double { max(red, max(green, blue)) }
	
	var trough: Double { min(red, min(green, blue)) }
	
	var saturation: Double { peak > 0 ? (peak - trough) / peak : 0 }
	
	var hue: Double {
		let span = peak - trough
		guard span > 0 else { return 0 }
		let turn: Double
		
		switch peak {
		case red: turn = (green - blue) / span / 6
		case green: turn = (2 + (blue - red) / span) / 6
		default: turn = (4 + (red - green) / span) / 6
		}
		
		return turn - turn.rounded(.down)
	}
	
	var normalised: LightColor { peak > 0 ? self * (1 / peak) : self }
	
	var clamped: LightColor {
		LightColor(red: min(max(red, 0), 1), green: min(max(green, 0), 1), blue: min(max(blue, 0), 1))
	}
	
	var color: Color {
		let c = clamped
		return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
	}
	
	var contrastingInk: Color {
		let c = clamped
		let luma = 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
		return luma > 0.55 ? .black : .white
	}
	
	func distance(to other: LightColor) -> Double {
		let dr = red - other.red, dg = green - other.green, db = blue - other.blue
		return (dr * dr + dg * dg + db * db).squareRoot()
	}
	
	func dot(_ other: Self) -> Double {
		red * other.red + green * other.green + blue * other.blue
	}
	
	static func + (lhs: Self, rhs: Self) -> Self {
		LightColor(red: lhs.red + rhs.red, green: lhs.green + rhs.green, blue: lhs.blue + rhs.blue)
	}
	
	static func - (lhs: Self, rhs: Self) -> Self {
		LightColor(red: lhs.red - rhs.red, green: lhs.green - rhs.green, blue: lhs.blue - rhs.blue)
	}
	
	static func * (lhs: Self, rhs: Double) -> Self {
		LightColor(red: lhs.red * rhs, green: lhs.green * rhs, blue: lhs.blue * rhs)
	}
}
