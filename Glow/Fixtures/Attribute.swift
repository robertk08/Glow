import SwiftUI

nonisolated enum Attribute: String, Codable, Sendable, CaseIterable, Identifiable {
	case dimmer
	case red, green, blue, white, amber, uv, lime
	case cyan, magenta, yellow
	case hue, saturation
	case colorTemperature, tint, cri
	case colorWheel, colorMacro, colorFade
	case pan, tilt, panTiltSpeed, positionMacro
	case shutter, prism, prismRotation, focus, zoom, iris, frost
	case gobo, goboRotation, gobo2, gobo2Rotation
	case dimmerCurve, program, programSpeed, sound, speed, reset, control, custom
	
	var id: String { rawValue }
	
	static let emitters: Set<Attribute> = [.red, .green, .blue, .white, .amber, .uv, .lime, .cyan, .magenta, .yellow]
	
	var isEmitter: Bool { Self.emitters.contains(self) }
	
	var group: FeatureGroup {
		switch self {
		case .dimmer, .dimmerCurve: .dimmer
		case .red, .green, .blue, .white, .amber, .uv, .lime: .color
		case .cyan, .magenta, .yellow: .color
		case .hue, .saturation, .colorTemperature, .tint, .cri: .color
		case .colorWheel, .colorMacro, .colorFade: .color
		case .pan, .tilt, .panTiltSpeed, .positionMacro: .position
		case .shutter, .prism, .prismRotation, .focus, .zoom, .iris, .frost: .beam
		case .gobo, .goboRotation, .gobo2, .gobo2Rotation: .gobo
		case .program, .programSpeed, .sound, .speed, .reset, .control, .custom: .control
		}
	}
	
	var name: String {
		switch self {
		case .dimmer: "Dimmer"
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
		case .hue: "Hue"
		case .saturation: "Saturation"
		case .colorTemperature: "Color temperature"
		case .tint: "Tint"
		case .cri: "Color rendering"
		case .colorWheel: "Color wheel"
		case .colorMacro: "Color preset"
		case .colorFade: "Color crossfade"
		case .pan: "Pan"
		case .tilt: "Tilt"
		case .panTiltSpeed: "Movement speed"
		case .positionMacro: "Movement macro"
		case .shutter: "Shutter"
		case .prism: "Prism"
		case .prismRotation: "Prism rotation"
		case .focus: "Focus"
		case .zoom: "Zoom"
		case .iris: "Iris"
		case .frost: "Frost"
		case .gobo: "Gobo"
		case .goboRotation: "Gobo rotation"
		case .gobo2: "Gobo wheel 2"
		case .gobo2Rotation: "Gobo 2 rotation"
		case .dimmerCurve: "Dimmer curve"
		case .program: "Program"
		case .programSpeed: "Program speed"
		case .sound: "Sound"
		case .speed: "Speed"
		case .reset: "Reset"
		case .control: "Control"
		case .custom: "Channel"
		}
	}
	
	var symbol: String {
		switch self {
		case .dimmer: "sun.max"
		case .pan, .tilt, .panTiltSpeed, .positionMacro: "move.3d"
		case .shutter: "bolt"
		case .gobo, .gobo2, .goboRotation, .gobo2Rotation: "circle.hexagongrid"
		case .zoom: "arrow.up.left.and.arrow.down.right"
		case .focus: "camera.metering.spot"
		case .iris: "camera.aperture"
		case .frost: "cloud.fog"
		case .prism, .prismRotation: "triangle"
		default: group.symbol
		}
	}
	
	var color: Color? { Emitter.light(of: self)?.color }
}
