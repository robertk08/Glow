import SwiftUI

nonisolated enum ChannelRole: String, Codable, Sendable, CaseIterable, Identifiable {
	case intensity, shutter
	case red, green, blue, white, amber, uv, lime, cyan, magenta, yellow
	case colorTemperature, colorWheel, colorMacro
	case pan, tilt, movementSpeed
	case gobo, goboRotation, prism, prismRotation, focus, zoom, iris, frost
	case function, reset, program, programSpeed, sound, speed, custom
	
	var id: String { rawValue }
	
	static let emitters: Set<ChannelRole> = [
		.red, .green, .blue, .white, .amber, .uv, .lime, .cyan, .magenta, .yellow,
	]
	
	var isEmitter: Bool { Self.emitters.contains(self) }
	
	var name: String {
		switch self {
		case .intensity: "Brightness"
		case .shutter: "Shutter"
		case .red: "Red"
		case .green: "Green"
		case .blue: "Blue"
		case .white: "White"
		case .amber: "Amber"
		case .uv: "UV"
		case .lime: "Lime"
		case .cyan: "Cyan"
		case .magenta: "Magenta"
		case .yellow: "Yellow"
		case .colorTemperature: "Colour temperature"
		case .colorWheel: "Colour wheel"
		case .colorMacro: "Colour macro"
		case .pan: "Pan"
		case .tilt: "Tilt"
		case .movementSpeed: "Movement speed"
		case .gobo: "Gobo"
		case .goboRotation: "Gobo rotation"
		case .prism: "Prism"
		case .prismRotation: "Prism rotation"
		case .focus: "Focus"
		case .zoom: "Zoom"
		case .iris: "Iris"
		case .frost: "Frost"
		case .function: "Function"
		case .reset: "Reset"
		case .program: "Program"
		case .programSpeed: "Program speed"
		case .sound: "Sound"
		case .speed: "Speed"
		case .custom: "Channel"
		}
	}
	
	var color: Color? {
		switch self {
		case .red: .red
		case .green: .green
		case .blue: .blue
		case .white: Color(white: 0.9)
		case .amber: .orange
		case .uv: .purple
		case .lime: Color(red: 0.75, green: 1, blue: 0.2)
		case .cyan: .cyan
		case .magenta: Color(red: 1, green: 0, blue: 1)
		case .yellow: .yellow
		default: nil
		}
	}
}
