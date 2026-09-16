import SwiftUI

/// Direct control of every channel a fixture occupies.
///
/// The escape hatch: whatever the app does or does not understand about a
/// fixture, this reaches every slot it owns. Rendered inside a `Form`, so it
/// produces `Section`s rather than a container of its own.
struct FixtureChannelControl: View {
    let control: FixtureControl
    let startAddress: DMXAddress

    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup("All \(control.profile.channelCount) channels", isExpanded: $isExpanded) {
                ForEach(control.profile.channels) { channel in
                    ChannelFader(
                        title: channel.name,
                        subtitle: control.address(of: channel).map { "DMX \($0.rawValue)" },
                        tint: channel.role.mixingTint,
                        value: control.binding(for: channel)
                    )
                }
            }
        } header: {
            Text("Channels")
        } footer: {
            Text("Patched at \(startAddress.rawValue), using \(control.profile.channelCount) channels.")
        }
    }
}
