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
		case .uv: "UV"
		case .cri: "Color rendering"
		case .colorMacro: "Color preset"
		case .colorFade: "Color crossfade"
		case .panTiltSpeed: "Movement speed"
		case .positionMacro: "Movement macro"
		case .gobo2: "Gobo wheel 2"
		case .custom: "Channel"
		default: Spoken.words(rawValue)
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
