import SwiftUI

/// Blackout: hold to engage, tap to restore.
///
/// The two directions deliberately cost different amounts. Blackout is the one
/// control that can end a show by being brushed with a thumb in a dark room,
/// and it is also the one you may need in a hurry, so going dark takes a
/// deliberate hold and coming back takes a single tap. A confirmation dialog
/// was the obvious alternative and is wrong twice over: it is slow in the
/// direction that has to be fast, and the HIG reserves confirmation for things
/// you cannot undo.
///
/// Nothing here is destructive. Blackout is an output stage inside
/// ``ConsoleEngine`` and never touches the universe, so restoring brings the
/// look back exactly. The labels say so, because a control that reads as
/// irreversible gets treated as irreversible.
struct BlackoutButton: View {
    @Environment(AppModel.self) private var model

    /// Icon-only until it is engaged, for a navigation bar. The title comes
    /// back the moment blackout is on: discreet while idle, loud while it
    /// matters.
    var compact = false

    /// Long enough that a knuckle or a pocket cannot do it, short enough to
    /// still be an emergency control.
    private static let holdDuration = 0.45

    @State private var holdProgress: Double = 0

    private var isOn: Bool { model.engine.blackout }

    var body: some View {
        Group {
            if isOn {
                Button { model.engine.blackout = false } label: { label }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
            } else {
                armControl
            }
        }
        .animation(.snappy, value: isOn)
        .onChange(of: isOn) { holdProgress = 0 }
        .sensoryFeedback(trigger: isOn) { _, nowOn in nowOn ? .warning : .success }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Blackout")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(
            isOn
                ? "Restores the rig to the look it had."
                : "Takes every fixture to zero. The look is kept and comes back when you restore."
        )
        // VoiceOver cannot express a hold, and its activate gesture is already
        // as deliberate as the hold was there to make the touch.
        .accessibilityAction { model.engine.blackout.toggle() }
    }

    /// The idle state. Not a `Button`: a button that ignores taps is a bug
    /// report, so this is a hold target that shows its own progress instead.
    private var armControl: some View {
        Group {
            // A navigation bar is already glass. Laying more on top of it
            // frosts the bar rather than producing a button.
            if compact {
                padded.foregroundStyle(Color.red)
            } else {
                padded
                    .foregroundStyle(Color.red)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .overlay {
            // Fills over exactly the hold duration, so a too-short press reads
            // as a too-short press rather than as nothing happening.
            Capsule()
                .trim(from: 0, to: holdProgress)
                .stroke(.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .contentShape(.capsule)
        .onLongPressGesture(minimumDuration: Self.holdDuration) {
            model.engine.blackout = true
        } onPressingChanged: { isPressing in
            withAnimation(
                isPressing ? .linear(duration: Self.holdDuration) : .snappy(duration: 0.2)
            ) {
                holdProgress = isPressing ? 1 : 0
            }
        }
    }

    private var padded: some View {
        label
            .padding(.horizontal, compact ? 10 : 16)
            .padding(.vertical, compact ? 7 : 11)
    }

    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: isOn ? "lightbulb.slash.fill" : "lightbulb.slash")
                .font(.body.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))

            if !compact || isOn {
                VStack(alignment: .leading, spacing: 1) {
                    Text(isOn ? "Blackout on" : "Blackout")
                        .font(.subheadline.weight(.semibold))
                    Text(isOn ? "Tap to restore" : "Hold")
                        .font(.caption2)
                        .opacity(0.75)
                }
                .lineLimit(1)
            }
        }
        .frame(maxWidth: compact ? nil : .infinity)
    }
}
