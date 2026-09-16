import SwiftUI

/// What a channel *means*, independent of which slot it happens to sit in.
///
/// The role is what lets one control surface drive fixtures with completely
/// different channel orders: the colour picker looks for `.red`/`.green`/
/// `.blue`, not for "channel 7". Anything the app has no specific UI for still
/// works — it falls back to a raw fader — so an unrecognised fixture is never
/// unusable, just less pretty.
nonisolated enum ChannelRole: String, Codable, Sendable, CaseIterable, Identifiable {
    // Intensity
    case intensity, shutter

    // Subtractive and additive colour
    case red, green, blue, white, amber, uv, lime, cyan, magenta, yellow
    case colorTemperature, colorWheel, colorMacro

    // Movement
    case pan, tilt, movementSpeed

    // Beam
    case gobo, goboRotation, prism, prismRotation, focus, zoom, iris, frost

    // Control
    case function, reset, program, programSpeed, sound, speed, custom

    var id: String { rawValue }

    /// Roles that together form an RGB-style colour mixer.
    static let colorMixing: Set<ChannelRole> = [
        .red, .green, .blue, .white, .amber, .uv, .lime, .cyan, .magenta, .yellow,
    ]

    var isColorMixing: Bool { Self.colorMixing.contains(self) }

    var localizedName: String {
        switch self {
        case .intensity: "Intensity"
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
        case .custom: "Custom"
        }
    }

    var symbolName: String {
        switch self {
        case .intensity: "sun.max"
        case .shutter: "camera.aperture"
        case .red, .green, .blue, .white, .amber, .uv, .lime, .cyan, .magenta, .yellow:
            "paintpalette"
        case .colorTemperature: "thermometer.sun"
        case .colorWheel, .colorMacro: "swatchpalette"
        case .pan: "arrow.left.and.right"
        case .tilt: "arrow.up.and.down"
        case .movementSpeed, .speed: "gauge.open.with.lines.needle.33percent"
        case .gobo: "circle.hexagongrid"
        case .goboRotation: "rotate.3d"
        case .prism, .prismRotation: "triangle"
        case .focus: "dot.circle.and.hand.point.up.left.fill"
        case .zoom: "arrow.up.left.and.arrow.down.right"
        case .iris: "circle.circle"
        case .frost: "snowflake"
        case .function: "slider.horizontal.3"
        case .reset: "arrow.counterclockwise"
        case .program, .programSpeed: "play.square"
        case .sound: "waveform"
        case .custom: "square.dashed"
        }
    }

    /// The colour a mixing channel contributes, for tinting its fader.
    var mixingTint: Color? {
        switch self {
        case .red: .red
        case .green: .green
        case .blue: .blue
        case .white: .white
        case .amber: .orange
        case .uv: .purple
        case .lime: Color(red: 0.75, green: 1.0, blue: 0.2)
        case .cyan: .cyan
        case .magenta: Color(red: 1.0, green: 0.0, blue: 1.0)
        case .yellow: .yellow
        default: nil
        }
    }
}
