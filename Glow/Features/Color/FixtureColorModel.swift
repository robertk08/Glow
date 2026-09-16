import SwiftUI

/// Something other than the emitters deciding what colour comes out.
///
/// Cheap fixtures put a macro channel next to their RGB channels, and above a
/// handful of DMX the macro wins outright — the faders go dead and nothing on
/// the fixture says so. The eleventh channel of the mini moving head in the
/// library does exactly this. Finding that out by waggling a red fader at a
/// stubbornly green light is the single worst half hour in small-rig lighting,
/// so the UI states it instead.
nonisolated struct ColorOverride: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Built-in colours that replace the mix.
        case macro
        /// Glass in the beam, which filters whatever the mix produces.
        case wheel
    }

    let kind: Kind
    let channel: FixtureChannel
    /// The band the channel is sitting in now.
    let band: FixtureChannelRange?
    /// The band that hands control back to the emitters.
    let release: FixtureChannelRange?
}

/// The colour side of one fixture, worked out from its profile.
///
/// Created fresh on each render and never stored, exactly like the
/// ``FixtureControl`` it wraps: everything here is a question asked of the
/// universe right now.
@MainActor struct FixtureColorModel {
    let control: FixtureControl

    var profile: FixtureProfile { control.profile }

    // MARK: - What this fixture has

    /// Every emitter channel, in the order the profile lists them.
    var emitterChannels: [FixtureChannel] { profile.colorMixingChannels }

    /// The emitters the automatic mixer is allowed to spend. UV is not one of
    /// them — see ``Emitter/mixable(_:)``.
    var mixableRoles: [ChannelRole] { emitterChannels.map(\.role).filter(Emitter.mixable) }

    /// Whether there is a mix to control at all. A colour wheel head has none.
    var canMix: Bool { control.supportsColor }

    var hasUltraviolet: Bool { emitterChannels.contains { $0.role == .uv } }

    /// Channels whose named bands are themselves a colour choice.
    var bandedChannels: [FixtureChannel] {
        [profile.channel(role: .colorMacro), profile.channel(role: .colorWheel)].compactMap { $0 }
    }

    /// A channel that means colour temperature and nothing else.
    var temperatureChannel: FixtureChannel? { profile.channel(role: .colorTemperature) }

    /// Whether asking this fixture for a particular white is meaningful.
    ///
    /// A white emitter is the line. Red, green and blue alone can *imitate* a
    /// warm white, and the presets do, but sweeping a continuous temperature
    /// across three narrow dies gives a tinted wash rather than a white, and
    /// offering the slider would be promising something the fixture cannot do.
    var canExpressTemperature: Bool {
        temperatureChannel != nil || mixableRoles.contains(.white)
    }

    // MARK: - What the fixture is doing now

    var currentMix: EmitterMix {
        var mix = EmitterMix()
        for channel in emitterChannels {
            mix[channel.role] = Double(control.value(of: channel)) / 255
        }
        return mix
    }

    /// The colour the emitters are making, UV included, so the swatch does not
    /// quietly lie when someone has the UV die up.
    var renderedColor: LightColor { currentMix.light.normalised }

    var colorName: String { ColorVocabulary.name(of: renderedColor) }

    /// How hard the hardest emitter is being driven, 0...1.
    ///
    /// On a fixture with no dimmer this *is* the intensity — ``FixtureControl``
    /// reads brightness the same way — which is why every colour change has to
    /// put it back exactly where it found it.
    var level: Double { currentMix.peak }

    /// The temperature the fixture is showing, or `nil` when it is showing a
    /// colour rather than a white.
    var kelvin: Double? { ColorTemperature.nearest(to: renderedColor) }

    // MARK: - Changing colour

    /// Applies a recipe without touching brightness.
    ///
    /// The recipe says the ratio between emitters; the fixture's current peak
    /// says how much of it to pour. Keeping that peak is what stops a tap on
    /// "Blue" from also being a tap on the dimmer, on the fixtures where the
    /// colour channels *are* the dimmer.
    func apply(_ mix: EmitterMix) {
        // Nothing is lit, so there is no brightness to preserve — come up at
        // full, the same call ``FixtureControl.intensity`` makes in the
        // mirror-image case. Choosing a colour on a dark fixture and getting
        // nothing would read as a broken control.
        let scale = level > 0 ? level : 1
        let recipe = mix.normalised

        for channel in emitterChannels {
            control.setChannelFraction(channel.role, recipe[channel.role] * scale)
        }
    }

    func apply(_ preset: ColorPreset) {
        apply(preset.mix(with: mixableRoles))
    }

    func apply(hue: Double, saturation: Double) {
        apply(.mixing(LightColor(hue: hue, saturation: saturation), with: mixableRoles))
    }

    func apply(kelvin: Double) {
        apply(.white(kelvin: kelvin, with: mixableRoles))
    }

    /// Whether the fixture is showing this preset right now, so it can carry a
    /// tick rather than the person having to recognise it by colour.
    func isShowing(_ preset: ColorPreset) -> Bool {
        guard level > 0 else { return false }
        return currentMix.matches(preset.mix(with: mixableRoles))
    }

    // MARK: - Who is in charge

    /// Non-`nil` when a macro or wheel is currently beating the emitters.
    var override: ColorOverride? {
        guard canMix else { return nil }

        for channel in bandedChannels {
            let value = control.value(of: channel)
            let release = Self.releaseBand(of: channel)
            if let release, release.contains(value) { continue }

            return ColorOverride(
                kind: channel.role == .colorWheel ? .wheel : .macro,
                channel: channel,
                band: channel.range(containing: value),
                release: release
            )
        }

        return nil
    }

    /// Puts a banded channel back where it stops interfering.
    func release(_ override: ColorOverride) {
        guard let release = override.release else { return }
        control.setValue(release.representativeValue, of: override.channel)
    }

    /// The band that leaves the emitters in charge.
    ///
    /// A profile that says which band this is wins. Otherwise fall back to
    /// matching the wording manufacturers use, and then to the lowest band,
    /// which is the convention even when the label is unhelpful.
    static func releaseBand(of channel: FixtureChannel) -> FixtureChannelRange? {
        if let declared = channel.ranges.first(where: \.releasesMix) { return declared }

        let hints = ["mix", "rgb", "faders active", "no function", "off", "open", "manual"]

        if let named = channel.ranges.first(where: { range in
            hints.contains { range.label.localizedCaseInsensitiveContains($0) }
        }) {
            return named
        }

        return channel.ranges.min { $0.from < $1.from }
    }

    /// One sentence saying which control the fixture is currently obeying.
    var authorityStatement: String {
        if let override {
            let band = override.band.map { "“\($0.label)”" } ?? "value \(control.value(of: override.channel))"
            switch override.kind {
            case .macro:
                return "“\(override.channel.name)” is at \(band). While it is there the fixture shows its own built-in colour and ignores the emitters entirely."
            case .wheel:
                return "“\(override.channel.name)” is at \(band), so glass sits in the beam and tints whatever the emitters produce."
            }
        }

        if let channel = bandedChannels.first, let release = Self.releaseBand(of: channel) {
            return "The emitters decide the colour: “\(channel.name)” is at “\(release.label)” and out of the way."
        }

        return "The emitters decide the colour."
    }
}
