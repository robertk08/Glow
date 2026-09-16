import SwiftUI

/// A colour of light, as plain sRGB fractions.
///
/// `Color` can carry this but cannot do arithmetic with it, and mixing is all
/// arithmetic: adding emitters together, subtracting what one emitter already
/// supplies, measuring how far a mix sits from the blackbody curve.
///
/// Brightness is deliberately absent. A `LightColor` is a direction, not a
/// length — how hard the fixture runs belongs to the intensity control, and
/// keeping it out of this type is what stops the colour UI from quietly
/// dimming a fixture every time someone picks a new colour.
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

    /// Scaled so the strongest component sits at 1, which is the only form in
    /// which two colours can be compared without brightness getting a vote.
    var normalised: LightColor { peak > 0 ? self * (1 / peak) : self }

    /// Clamped to the unit cube. The subtraction in the emitter fit can leave
    /// a component a hair below zero through rounding, and a negative
    /// component turns into a wrapped `UInt8` further down.
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

    /// Dot product, for asking how much of this colour an emitter can supply.
    func dot(_ other: Self) -> Double {
        red * other.red + green * other.green + blue * other.blue
    }
}

// MARK: - Hue and saturation

nonisolated extension LightColor {
    /// 0...1 around the colour wheel. Undefined for a grey, where it reads 0.
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

    /// 0 for a white, 1 for a fully saturated colour.
    var saturation: Double {
        let high = peak
        guard high > 0 else { return 0 }
        return (high - min(red, min(green, blue))) / high
    }

    /// A fully bright colour at this hue and saturation. Brightness is fixed
    /// at 1 on purpose: this is the only form the picker ever produces, so
    /// dragging hue or saturation cannot change how bright the fixture is.
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

// MARK: - Display

nonisolated extension LightColor {
    /// The swatch colour. Constant rather than adaptive: it stands for what
    /// the lamp is emitting, which does not change when the phone switches to
    /// dark mode.
    var color: Color {
        let c = clamped
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
    }

    /// Black or white, whichever stays readable on top of this colour. Used
    /// for the tick on a selected swatch, which has to survive a pale amber
    /// and a deep blue with the same code path.
    var contrastingInk: Color {
        let c = clamped
        // Rec. 709 luma: the eye weights green far above blue, so a plain
        // average would call a saturated blue "bright" and put black on it.
        let luma = 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
        return luma > 0.55 ? .black : .white
    }
}

// MARK: - Colour temperature

/// The blackbody curve, and the business of recognising a point on it.
nonisolated enum ColorTemperature {
    /// What the temperature control offers. Wider than a camera's range on
    /// purpose: stage fixtures are asked for deliberately over-warm and
    /// over-cool looks that a photographic white balance never is.
    static let range: ClosedRange<Double> = 2000...10000

    static let warm: Double = 2700
    static let neutral: Double = 4000
    static let cool: Double = 6500

    /// The colour of a blackbody radiator at `kelvin`, normalised.
    ///
    /// Tanner Helland's curve fit to the Planckian locus — an approximation,
    /// but one that has been checked against real light for twenty years and
    /// is far closer than anything hand-picked.
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

    /// Sampled once. `nearest(to:)` runs on every redraw of the temperature
    /// row, including every frame of a drag, and the curve never changes.
    private static let locus: [Sample] = stride(from: range.lowerBound, through: range.upperBound, by: 50)
        .map { Sample(kelvin: $0, light: light(kelvin: $0)) }

    /// The temperature a colour *is*, or `nil` when it is not a white at all.
    ///
    /// This is what lets the temperature slider read back rather than only
    /// write: tap "Warm white" and the slider moves to 2700 K, dial a deep
    /// blue and it stops claiming to describe the fixture.
    ///
    /// The tolerance is tight enough that a saturated amber — which sits just
    /// off the warm end of the curve — is still called amber.
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

// MARK: - Clamping off the main actor

extension Double {
    /// The app's own `clamped(to:)` sits in an extension on the far side of
    /// the domain, where the project's default actor isolation puts it on the
    /// main actor. Colour mixing is `nonisolated` value work and cannot reach
    /// it, and a differently named pair avoids quietly shadowing it for every
    /// other caller in the app.
    nonisolated var clampedToUnit: Double { min(max(self, 0), 1) }

    nonisolated func clampedTo(_ range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
