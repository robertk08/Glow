import SwiftUI

/// What each emitter looks like on its own, as sRGB.
///
/// Eyeball figures, not spectra. They only have to be good enough that adding
/// them up predicts what lands on the wall, and they are the whole reason a
/// beginner can ask for "warm white" without knowing the fixture has an amber
/// die in it.
nonisolated enum Emitter {
    static func light(of role: ChannelRole) -> LightColor? {
        switch role {
        case .red: LightColor(red: 1, green: 0, blue: 0)
        case .green: LightColor(red: 0, green: 1, blue: 0)
        case .blue: LightColor(red: 0, green: 0, blue: 1)
        // A "white" LED is a blue die under phosphor, so it is not neutral —
        // it lands near 6000 K, slightly short of green and blue.
        case .white: LightColor(red: 1, green: 0.96, blue: 0.92)
        case .amber: LightColor(red: 1, green: 0.55, blue: 0)
        case .lime: LightColor(red: 0.72, green: 1, blue: 0.16)
        case .cyan: LightColor(red: 0, green: 1, blue: 1)
        case .magenta: LightColor(red: 1, green: 0, blue: 1)
        case .yellow: LightColor(red: 1, green: 1, blue: 0)
        // Barely visible as violet, and mostly not visible at all — it makes
        // white shirts glow. Rendered so the swatch tells the truth when it is
        // up, but never chosen by the mixer; see `mixable`.
        case .uv: LightColor(red: 0.28, green: 0, blue: 0.85)
        default: nil
        }
    }

    /// The order the mixer spends emitters in.
    ///
    /// White first because it is by far the most light per channel, then the
    /// broad phosphor colours, and the narrow red/green/blue dies last to soak
    /// up whatever is left. Reversing this gives the same colour out of a much
    /// dimmer fixture, which is exactly the "why does this look so weak"
    /// complaint that sends people back to the fixture's own remote.
    static let mixingOrder: [ChannelRole] = [
        .white, .amber, .lime, .cyan, .magenta, .yellow, .red, .green, .blue,
    ]

    /// UV is excluded: it adds almost no visible light, so a mixer told to
    /// match a violet would happily reach for it and produce a fixture that
    /// looks switched off. It is reachable as a preset and as its own fader.
    static func mixable(_ role: ChannelRole) -> Bool { role != .uv && light(of: role) != nil }
}

/// How hard each emitter of one fixture is driven, 0...1.
nonisolated struct EmitterMix: Equatable, Sendable {
    private var levels: [ChannelRole: Double]

    init(_ levels: [ChannelRole: Double] = [:]) {
        self.levels = levels
    }

    subscript(role: ChannelRole) -> Double {
        get { levels[role] ?? 0 }
        set { levels[role] = newValue }
    }

    var peak: Double { levels.values.max() ?? 0 }

    /// Scaled so the hardest-driven emitter sits at 1. The mix is a recipe;
    /// how much of it to pour is the level's business.
    var normalised: EmitterMix {
        let peak = peak
        guard peak > 0 else { return self }
        return EmitterMix(levels.mapValues { $0 / peak })
    }

    /// The colour this mix actually produces.
    var light: LightColor {
        levels.reduce(LightColor.black) { total, entry in
            guard let emitter = Emitter.light(of: entry.key) else { return total }
            return total + emitter * entry.value
        }
    }

    /// Whether two recipes are the same look, ignoring how bright either is.
    /// Used to tick the preset that is currently showing.
    func matches(_ other: EmitterMix, tolerance: Double = 0.05) -> Bool {
        let lhs = normalised
        let rhs = other.normalised
        let roles = Set(lhs.levels.keys).union(rhs.levels.keys)
        return roles.allSatisfy { abs(lhs[$0] - rhs[$0]) <= tolerance }
    }
}

// MARK: - Fitting a colour onto real emitters

nonisolated extension EmitterMix {
    /// The emitter levels that add up to `target` on a fixture that has
    /// `available` emitters.
    ///
    /// Greedy subtraction: take as much of the colour as each emitter can
    /// supply without overshooting any channel, subtract what it contributed,
    /// move on. Because red, green and blue come last and can absorb any
    /// leftover, the result reproduces the target exactly rather than
    /// approximately — which is what lets the hue slider and the temperature
    /// slider read their own value back off the fixture instead of having to
    /// remember what they last wrote.
    ///
    /// The point of the ordering is the white and amber dies. Ask an RGBWA par
    /// for 2700 K and this spends the amber and white first and leaves red
    /// with a trickle, which is the mix an operator would dial by hand and
    /// nothing like the orange an RGB-only picker produces.
    static func mixing(_ target: LightColor, with available: [ChannelRole]) -> EmitterMix {
        let emitters = available.filter(Emitter.mixable)
        guard !emitters.isEmpty else { return EmitterMix() }

        var residual = target.normalised.clamped
        var mix = EmitterMix()

        for role in Emitter.mixingOrder where emitters.contains(role) {
            guard let emitter = Emitter.light(of: role) else { continue }

            // The most of this emitter that fits under the residual in every
            // channel at once. Any more and it overshoots one of them, which
            // shows up as a colour cast that no other emitter can take back.
            var amount = Double.infinity
            for (component, share) in [
                (residual.red, emitter.red), (residual.green, emitter.green), (residual.blue, emitter.blue),
            ] where share > 0 {
                amount = min(amount, component / share)
            }

            guard amount.isFinite, amount > 0 else { continue }
            amount = min(amount, 1)
            mix[role] = amount
            residual = (residual - emitter * amount).clamped
        }

        guard mix.peak > 0 else { return closestDirection(to: target, with: emitters) }
        return mix.normalised
    }

    /// For a fixture whose emitters cannot reach the colour at all — a
    /// subtractive CMY head asked for a saturated red, say. Projecting onto
    /// each emitter gives the nearest thing it can do; returning nothing would
    /// leave the fixture dark and look like a bug.
    private static func closestDirection(to target: LightColor, with emitters: [ChannelRole]) -> EmitterMix {
        var mix = EmitterMix()
        let direction = target.normalised

        for role in emitters {
            guard let emitter = Emitter.light(of: role) else { continue }
            let magnitude = emitter.dot(emitter)
            guard magnitude > 0 else { continue }
            mix[role] = (direction.dot(emitter) / magnitude).clampedToUnit
        }

        return mix.normalised
    }

    /// The mix for a white of a given colour temperature.
    static func white(kelvin: Double, with available: [ChannelRole]) -> EmitterMix {
        mixing(ColorTemperature.light(kelvin: kelvin), with: available)
    }
}

// MARK: - Naming a colour

/// Words for colours.
///
/// Every swatch, every slider and every VoiceOver value in the colour UI goes
/// through here. Hue on its own tells a third of a million people in the UK
/// nothing at all, and "the orange one" is useless over a headset even to
/// everyone else.
nonisolated enum ColorVocabulary {
    static func name(of light: LightColor) -> String {
        let colour = light.normalised

        guard colour.peak > 0 else { return "Off" }

        // A white has to be recognised before saturation is consulted:
        // 2700 K is a thoroughly orange set of sRGB numbers, and calling it
        // "orange" would be both true and completely unhelpful.
        if let kelvin = ColorTemperature.nearest(to: colour) {
            return whiteName(kelvin: kelvin)
        }

        if colour.saturation < 0.12 { return "White" }

        let name = hueName(colour.hue)
        return colour.saturation < 0.45 ? "Pale \(name.lowercased())" : name
    }

    static func whiteName(kelvin: Double) -> String {
        switch kelvin {
        case ..<2400: "Candle white"
        case ..<3100: "Warm white"
        case ..<4600: "Neutral white"
        case ..<5800: "Daylight white"
        default: "Cool white"
        }
    }

    /// Bands chosen so the names match what people say out loud about a stage
    /// wash, not so they divide the wheel evenly.
    static func hueName(_ hue: Double) -> String {
        switch (hue * 360).truncatingRemainder(dividingBy: 360) {
        case ..<12: "Red"
        case ..<32: "Orange"
        case ..<45: "Amber"
        case ..<64: "Yellow"
        case ..<80: "Lime"
        case ..<150: "Green"
        case ..<172: "Sea green"
        case ..<196: "Cyan"
        case ..<215: "Sky blue"
        case ..<250: "Blue"
        case ..<270: "Indigo"
        case ..<292: "Violet"
        case ..<320: "Magenta"
        case ..<345: "Pink"
        default: "Red"
        }
    }

    /// Spoken by VoiceOver on the hue slider: the angle is precise and the
    /// name is what anyone actually needs.
    static func hueDescription(_ hue: Double) -> String {
        "\(Int((hue * 360).rounded())) degrees, \(hueName(hue).lowercased())"
    }
}

// MARK: - Presets

/// One tap's worth of colour.
nonisolated struct ColorPreset: Identifiable, Equatable, Sendable {
    enum Recipe: Equatable, Sendable {
        /// A white, which spends the white and amber emitters when there are
        /// any and falls back to the blackbody curve on red/green/blue.
        case white(kelvin: Double)
        /// A colour, given at full saturation or pastel as written.
        case colour(LightColor)
        /// Straight to the UV die. Never produced by the mixer, so it needs
        /// its own way in.
        case ultraviolet
    }

    let name: String
    let recipe: Recipe

    var id: String { name }

    func mix(with emitters: [ChannelRole]) -> EmitterMix {
        switch recipe {
        case let .white(kelvin): .white(kelvin: kelvin, with: emitters)
        case let .colour(light): .mixing(light, with: emitters)
        case .ultraviolet: EmitterMix([.uv: 1])
        }
    }

    /// What the swatch shows: the colour this fixture will actually make, not
    /// the colour that was asked for. On an RGB-only par the "warm white"
    /// swatch is visibly more orange than on an RGBWA one, which is the truth
    /// and saves an argument with the wall later.
    func swatch(with emitters: [ChannelRole]) -> LightColor {
        mix(with: emitters).light.normalised
    }

    /// The presets worth a tap on a fixture with these emitters.
    ///
    /// Short on purpose. This list is read at arm's length in a dark room; a
    /// grid of forty swatches is slower to use than the hue slider underneath
    /// it.
    static func all(for emitters: [ChannelRole]) -> [ColorPreset] {
        var presets: [ColorPreset] = [
            ColorPreset(name: "Warm white", recipe: .white(kelvin: ColorTemperature.warm)),
            ColorPreset(name: "Neutral white", recipe: .white(kelvin: ColorTemperature.neutral)),
            ColorPreset(name: "Cool white", recipe: .white(kelvin: ColorTemperature.cool)),
            ColorPreset(name: "Red", recipe: .colour(LightColor(hue: 0, saturation: 1))),
            ColorPreset(name: "Amber", recipe: .colour(LightColor(hue: 0.105, saturation: 1))),
            ColorPreset(name: "Gold", recipe: .colour(LightColor(hue: 0.13, saturation: 0.62))),
            ColorPreset(name: "Pink", recipe: .colour(LightColor(hue: 0.94, saturation: 0.45))),
            ColorPreset(name: "Magenta", recipe: .colour(LightColor(hue: 0.86, saturation: 1))),
            ColorPreset(name: "Lavender", recipe: .colour(LightColor(hue: 0.75, saturation: 0.45))),
            ColorPreset(name: "Blue", recipe: .colour(LightColor(hue: 0.62, saturation: 1))),
            ColorPreset(name: "Cyan", recipe: .colour(LightColor(hue: 0.5, saturation: 1))),
            ColorPreset(name: "Green", recipe: .colour(LightColor(hue: 0.33, saturation: 1))),
        ]

        if emitters.contains(.uv) {
            presets.append(ColorPreset(name: "UV", recipe: .ultraviolet))
        }

        return presets
    }
}
