import SwiftUI

struct ChannelsView: View {
    let control: FixtureControl

    @State private var editing: FixtureParameter?
    @State private var entry = ""
    @State private var confirming: (FixtureParameter, ChannelRange)?

    var body: some View {
        List {
            ForEach(control.parameters) { parameter in
                Section {
                    ParameterRow(control: control, parameter: parameter) {
                        editing = parameter
                        entry = String(control.rawValue(of: parameter))
                    }

                    if !parameter.ranges.isEmpty {
                        Picker("Setting", selection: bandSelection(parameter)) {
                            ForEach(parameter.ranges) { range in
                                Text(range.label).tag(range.id)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(parameter.name)
                        Spacer()
                        Text("DMX \(control.addressLabel(of: parameter))")
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Channels")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Set \(editing?.name ?? "")", isPresented: .constant(editing != nil)) {
            TextField("0 to \(editing?.maximum ?? 255)", text: $entry)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) { editing = nil }
            Button("Set") {
                if let editing, let value = Int(entry) {
                    control.setRawValue(value, of: editing)
                }
                editing = nil
            }
        }
        .alert("Send \(confirming?.1.label ?? "")?", isPresented: .constant(confirming != nil)) {
            Button("Cancel", role: .cancel) { confirming = nil }
            Button("Send", role: .destructive) {
                if let (parameter, range) = confirming {
                    control.set(range.midpoint, of: parameter.coarse)
                }
                confirming = nil
            }
        } message: {
            Text("The light stops responding for a few seconds.")
        }
    }

    private func bandSelection(_ parameter: FixtureParameter) -> Binding<String> {
        Binding(
            get: { control.band(of: parameter)?.id ?? "" },
            set: { id in
                guard let range = parameter.ranges.first(where: { $0.id == id }) else { return }
                if range.requiresConfirmation {
                    confirming = (parameter, range)
                } else {
                    control.set(range.midpoint, of: parameter.coarse)
                }
            }
        )
    }
}

private struct ParameterRow: View {
    let control: FixtureControl
    let parameter: FixtureParameter
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let band = control.band(of: parameter) {
                    Text(band.label)
                        .foregroundStyle(.secondary)
                } else {
                    Text(parameter.role.name)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: edit) {
                    HStack(spacing: 6) {
                        Text(control.percent(of: parameter), format: .percent.precision(.fractionLength(0)))
                        Text("\(control.rawValue(of: parameter))")
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
                .buttonStyle(.plain)
            }
            .font(.subheadline)

            Slider(
                value: Binding(
                    get: { Double(control.rawValue(of: parameter)) },
                    set: { control.setRawValue(Int($0.rounded()), of: parameter) }
                ),
                in: 0...Double(parameter.maximum)
            )
            .tint(parameter.role.color)
        }
    }
}
