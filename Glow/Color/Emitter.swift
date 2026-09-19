import Foundation

nonisolated enum Emitter {
	static let mixingOrder: [Attribute] = [
		.white, .amber, .lime, .cyan, .magenta, .yellow, .red, .green, .blue,
	]
	
	static let flags: [Attribute] = [.cyan, .magenta, .yellow]
	
	static func light(of attribute: Attribute) -> LightColor? {
		switch attribute {
		case .red: LightColor(red: 1, green: 0, blue: 0)
		case .green: LightColor(red: 0, green: 1, blue: 0)
		case .blue: LightColor(red: 0, green: 0, blue: 1)
		case .white: LightColor(red: 1, green: 0.96, blue: 0.92)
		case .amber: LightColor(red: 1, green: 0.55, blue: 0)
		case .lime: LightColor(red: 0.72, green: 1, blue: 0.16)
		case .cyan: LightColor(red: 0, green: 1, blue: 1)
		case .magenta: LightColor(red: 1, green: 0, blue: 1)
		case .yellow: LightColor(red: 1, green: 1, blue: 0)
		case .uv: LightColor(red: 0.28, green: 0, blue: 0.85)
		default: nil
		}
	}
}
