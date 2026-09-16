import SwiftUI

/// The icons a fixture can be given.
///
/// A curated list rather than the whole SF Symbols catalogue: the point is to
/// tell one light apart from another at a glance in a dark room, and thirty
/// recognisable shapes do that better than nine thousand searchable ones.
///
/// Every name here has been checked against the system symbol catalogue. An
/// invented name renders as blank space, which is a silent failure and exactly
/// the kind that survives to the App Store.
nonisolated enum FixtureIcon {
    nonisolated struct Group: Identifiable, Sendable {
        var name: String
        var symbols: [String]
        var id: String { name }
    }

    static let fallback = "lightbulb"

    static let groups: [Group] = [
        Group(name: "Heads", symbols: [
            "light.beacon.max", "scope", "target", "move.3d", "rotate.3d",
        ]),
        Group(name: "Washes and pars", symbols: [
            "light.panel", "lightbulb.max", "lightbulb", "lightbulb.min",
            "light.max", "light.min", "sun.max", "sun.min",
        ]),
        Group(name: "Bars and strips", symbols: [
            "light.strip.2", "rectangle.portrait", "square.stack.3d.up", "display",
        ]),
        Group(name: "Effects", symbols: [
            "laser.burst", "sparkles", "sparkle", "star", "party.popper",
            "fireworks", "rays", "camera.aperture", "circle.hexagongrid",
        ]),
        Group(name: "Atmospherics", symbols: [
            "smoke", "cloud.fog", "wind", "snowflake", "drop", "flame",
        ]),
        Group(name: "Practicals", symbols: [
            "lamp.desk", "lamp.table", "lamp.floor", "lamp.ceiling",
            "chandelier", "flashlight.on.fill",
        ]),
        Group(name: "Other", symbols: [
            "bolt", "bolt.horizontal", "waveform", "speaker.wave.2",
            "theatermasks", "video", "tv", "cube",
        ]),
    ]

    static let all: [String] = groups.flatMap(\.symbols)

    static func isKnown(_ symbol: String) -> Bool { all.contains(symbol) }
}

/// A colour label for a fixture, so a rig reads as groups rather than a list.
///
/// A fixed palette rather than a free colour picker: these sit next to the
/// fixture's *output* colour, and two arbitrary colours side by side would be
/// impossible to tell apart as "what this light is" versus "what it is doing".
nonisolated enum FixtureTint: String, CaseIterable, Identifiable, Sendable {
    case none, red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown

    var id: String { rawValue }

    var color: Color? {
        switch self {
        case .none: nil
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        }
    }

    var localizedName: String {
        switch self {
        case .none: "No colour"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .mint: "Mint"
        case .teal: "Teal"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        case .brown: "Brown"
        }
    }
}
