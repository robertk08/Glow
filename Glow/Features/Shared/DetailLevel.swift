import SwiftUI

/// How much of a fixture a screen puts on show.
///
/// # The disclosure architecture
///
/// Glow has two audiences with nothing in common. One bought a cheap moving
/// head, wants it blue, and has never heard of DMX. The other runs a GrandMA3
/// and wants channel 11 at 137. Every screen resolves that the same way, and
/// this type is the resolution.
///
/// Content is sorted into three tiers, and a screen lays them out in that
/// order, top to bottom, always:
///
/// - **Tier 1 — what the light does.** Brightness, colour, where it points,
///   blackout. Never behind a disclosure, never behind a picker, never
///   abbreviated. Someone who touches nothing else gets a working light.
/// - **Tier 2 — what *this* fixture can do**, in the words its own manual
///   uses: shutter bands, gobo wheels, colour macros. Always on screen,
///   always below tier 1, always under a header that says what it is. Further
///   down, not hidden.
/// - **Tier 3 — the wire.** Every channel, by DMX number, as raw bytes. This
///   is the only tier ``full`` reveals and ``simple`` withholds.
///
/// So the switch below is not a beginner mode and an expert mode. Tiers 1 and
/// 2 are identical in both. ``full`` adds the numbers: DMX addresses, raw
/// values, per-axis faders next to the pad, the auxiliary mixing channels.
/// That is the whole difference, which is what makes the control safe to put
/// in front of someone who does not yet know what it means — flipping it can
/// never take a control away.
///
/// # Where the switch lives
///
/// One picker, on the fixture screen, above the controls it governs. Not in
/// Settings, not in a toolbar menu, not per fixture: the person who needs
/// tier 3 needs it on every fixture and every screen, and the person who does
/// not should never have to go looking for the thing they turned on by
/// accident. It is stored under ``storageKey`` and any screen that has tier 3
/// content reads the same key:
///
/// ```swift
/// @AppStorage(DetailLevel.storageKey) private var detail = DetailLevel.simple
/// ```
///
/// # The rule that is easy to break
///
/// A screen may not invent a fourth tier, and may not move something down a
/// tier because the screen got crowded. If a control does not fit, the screen
/// is wrong, not the tier. The moment one screen puts colour behind a
/// disclosure "just here", the app stops having an architecture and starts
/// having opinions.
nonisolated enum DetailLevel: String, CaseIterable, Identifiable, Sendable {
    /// Tiers 1 and 2. No DMX numbers anywhere.
    case simple

    /// Tiers 1, 2 and 3 — the same controls, plus the addresses and raw
    /// values behind them.
    case full

    var id: String { rawValue }

    /// The key every screen reads. Changing it silently resets everyone's
    /// choice to ``simple``, so it is spelled once, here.
    static let storageKey = "controls.detailLevel"

    var localizedName: String {
        switch self {
        case .simple: "Simple"
        case .full: "Full"
        }
    }

    var symbolName: String {
        switch self {
        case .simple: "slider.horizontal.3"
        case .full: "slider.vertical.3"
        }
    }

    /// Shown under the picker, so picking is not a guess. Phrased as what you
    /// get rather than who you are — nobody self-identifies as a beginner.
    var explanation: String {
        switch self {
        case .simple:
            "Brightness, colour, position, and the options built into the fixture."
        case .full:
            "The same controls, plus DMX addresses, raw values and every channel."
        }
    }

    /// True when addresses and 0–255 values belong on screen.
    var showsRawValues: Bool { self == .full }
}

/// The picker itself, so every screen offering the switch offers the same one.
struct DetailLevelPicker: View {
    @Binding var selection: DetailLevel

    var body: some View {
        Picker("Detail", selection: $selection) {
            ForEach(DetailLevel.allCases) { level in
                Text(level.localizedName).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Level of detail")
    }
}
