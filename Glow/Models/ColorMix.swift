import SwiftUI

nonisolated struct LightColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let black = LightColor(red: 0, green: 0, blue: 0)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var peak: Double { max(red, max(green, blue)) }

    var normalised: LightColor { peak > 0 ? self * (1 / peak) : self }

    var clamped: LightColor {
        LightColor(
            red: red.clampedToUnit,
            green: green.clampedToUnit,
            blue: blue.clampedToUnit
        )
    }

    func distance(to other: LightColor) -> Double {
        let dr = red - other.red, dg = green - other.green, db = blue - other.blue
        return (dr * dr + dg * dg + db * db).squareRoot()
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

    func dot(_ other: Self) -> Double {
        red * other.red + green * other.green + blue * other.blue
    }
}

nonisolated extension LightColor {
    var hue: Double {
        let high = peak
        let low = min(red, min(green, blue))
        let delta = high - low
        guard delta > 0 else { return 0 }

        let sector: Double =
            if high == red { (green - blue) / delta }
            else if high == green { (blue - red) / delta + 2 }
            else { (red - green) / delta + 4 }

        let turns = sector / 6
        return turns < 0 ? turns + 1 : turns
    }

    var saturation: Double {
        let high = peak
        guard high > 0 else { return 0 }
        return (high - min(red, min(green, blue))) / high
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
}

nonisolated extension LightColor {
    var color: Color {
        let c = clamped
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
    }

    var contrastingInk: Color {
        let c = clamped
        let luma = 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
        return luma > 0.55 ? .black : .white
    }
}

nonisolated enum ColorTemperature {
    static let range: ClosedRange<Double> = 2000...10000

    static let warm: Double = 2700
    static let neutral: Double = 4000
    static let cool: Double = 6500

    static func light(kelvin: Double) -> LightColor {
        let t = kelvin.clampedTo(1000...40000) / 100

        let red: Double = t <= 66 ? 255 : 329.698_727_446 * pow(t - 60, -0.133_204_759_2)

        let green: Double =
            t <= 66
            ? 99.470_802_586_1 * log(t) - 161.119_568_166_1
            : 288.122_169_528_3 * pow(t - 60, -0.075_514_849_2)

        let blue: Double =
            if t >= 66 { 255 }
            else if t <= 19 { 0 }
            else { 138.517_731_223_1 * log(t - 10) - 305.044_792_730_7 }

        return LightColor(
            red: red / 255,
            green: green / 255,
            blue: blue / 255
        ).clamped.normalised
    }

    private struct Sample: Sendable {
        let kelvin: Double
        let light: LightColor
    }

    private static let locus: [Sample] = stride(from: range.lowerBound, through: range.upperBound, by: 50)
        .map { Sample(kelvin: $0, light: light(kelvin: $0)) }

    static func nearest(to light: LightColor, tolerance: Double = 0.045) -> Double? {
        let target = light.normalised
        var best: Sample?
        var bestDistance = Double.infinity

        for sample in locus {
            let distance = sample.light.distance(to: target)
            if distance < bestDistance {
                bestDistance = distance
                best = sample
            }
        }

        guard let best, bestDistance <= tolerance else { return nil }
        return best.kelvin
    }
}

nonisolated extension Double {
    var clampedToUnit: Double { min(max(self, 0), 1) }

    func clampedTo(_ range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

nonisolated enum Emitter {
    static func light(of role: ChannelRole) -> LightColor? {
        switch role {
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

    static let mixingOrder: [ChannelRole] = [
        .white, .amber, .lime, .cyan, .magenta, .yellow, .red, .green, .blue,
    ]

    static func mixable(_ role: ChannelRole) -> Bool { role != .uv && light(of: role) != nil }
}

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

    var normalised: EmitterMix {
        let peak = peak
        guard peak > 0 else { return self }
        return EmitterMix(levels.mapValues { $0 / peak })
    }

    var light: LightColor {
        levels.reduce(LightColor.black) { total, entry in
            guard let emitter = Emitter.light(of: entry.key) else { return total }
            return total + emitter * entry.value
        }
    }

    func matches(_ other: EmitterMix, tolerance: Double = 0.05) -> Bool {
        let lhs = normalised
        let rhs = other.normalised
        let roles = Set(lhs.levels.keys).union(rhs.levels.keys)
        return roles.allSatisfy { abs(lhs[$0] - rhs[$0]) <= tolerance }
    }
}

nonisolated extension EmitterMix {
    static func mixing(_ target: LightColor, with available: [ChannelRole]) -> EmitterMix {
        let emitters = available.filter(Emitter.mixable)
        guard !emitters.isEmpty else { return EmitterMix() }

        var residual = target.normalised.clamped
        var mix = EmitterMix()

        for role in Emitter.mixingOrder where emitters.contains(role) {
            guard let emitter = Emitter.light(of: role) else { continue }

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

    static func white(kelvin: Double, with available: [ChannelRole]) -> EmitterMix {
        mixing(ColorTemperature.light(kelvin: kelvin), with: available)
    }
}

nonisolated enum ColorVocabulary {
    static func name(of light: LightColor) -> String {
        let colour = light.normalised

        guard colour.peak > 0 else { return "Off" }

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

    static func hueDescription(_ hue: Double) -> String {
        "\(Int((hue * 360).rounded())) degrees, \(hueName(hue).lowercased())"
    }
}

nonisolated struct ColorPreset: Identifiable, Equatable, Sendable {
    enum Recipe: Equatable, Sendable {
        case white(kelvin: Double)
        case colour(LightColor)
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

    func swatch(with emitters: [ChannelRole]) -> LightColor {
        mix(with: emitters).light.normalised
    }

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
