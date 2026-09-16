import SwiftUI

struct ChannelList: View {
    let control: FixtureControl

    @State private var editing: ProfileChannel?
    @State private var entry = ""

    var body: some View {
        List {
            ForEach(control.profile.channels) { channel in
                ChannelRow(control: control, channel: channel) {
                    editing = channel
                    entry = String(control.value(of: channel))
                }
            }
        }
        .navigationTitle("Channels")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Set \(editing?.name ?? "")", isPresented: .constant(editing != nil)) {
            TextField("0 to 255", text: $entry)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) { editing = nil }
            Button("Set") {
                if let editing, let value = Int(entry) {
                    control.set(UInt8(value.clamped(to: 0...255)), of: editing)
                }
                editing = nil
            }
        }
    }
}

private struct ChannelRow: View {
    let control: FixtureControl
    let channel: ProfileChannel
    let edit: () -> Void

    private var value: UInt8 { control.value(of: channel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(channel.name)

                Spacer()

                Button {
                    edit()
                } label: {
                    Text("\(value)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Slider(value: control.binding(channel), in: 0...255, step: 1) {
                Text(channel.name)
            }
            .tint(channel.role.color)

            if let band = channel.range(containing: value) {
                Text(band.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(value)")
    }
}
