import SwiftUI

/// A button in a `Form` that says what it will do before you do it.
///
/// Exists because the actions on a lighting console are verbs borrowed from
/// desks people have never used. "Home" is one word and three separate changes
/// to the rig, and a row that only says "Home" is a row nobody presses twice.
struct ActionRow: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
    }
}
