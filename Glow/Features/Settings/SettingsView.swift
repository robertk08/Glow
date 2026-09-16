import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var manualHost = ""
    @State private var isEditingHost = false

    var body: some View {
        @Bindable var engine = model.engine

        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status") { ConnectionStatusView() }
                    LabeledContent("Node", value: model.endpoint.displayName)

                    if let status = model.engine.nodeStatus {
                        LabeledContent("Firmware", value: status.firmware)
                        LabeledContent("Uptime", value: Duration.seconds(status.uptime).formatted(.units(allowed: [.days, .hours, .minutes])))
                    }

                    if case let .failed(reason) = model.engine.connection {
                        Text(reason).font(.footnote).foregroundStyle(.red)
                    }

                    Button("Reconnect now", systemImage: "arrow.clockwise") {
                        model.engine.retry()
                    }
                    Button("Identify", systemImage: "light.beacon.max") {
                        model.engine.identify()
                    }
                    .disabled(!model.engine.connection.isConnected)
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Glow talks straight to the node over your Wi-Fi. Both have to be on the same network.")
                }

                Section {
                    if model.discovery.endpoints.isEmpty {
                        HStack {
                            Text("Looking for nodes…")
                                .foregroundStyle(.secondary)
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        ForEach(model.discovery.endpoints) { endpoint in
                            Button {
                                model.endpoint = endpoint
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(endpoint.displayName)
                                        Text(endpoint.host)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if endpoint.id == model.endpoint.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Found on this network")
                } footer: {
                    if model.discovery.permissionDenied {
                        Text("Glow can't search the local network. Turn on Local Network for Glow in Settings › Privacy & Security.")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    HStack {
                        TextField("Host or IP", text: $manualHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit(applyManualHost)
                        Button("Use") { applyManualHost() }
                            .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Connect manually")
                } footer: {
                    Text("Use this when Bonjour discovery is blocked, which is common on guest and mesh networks. The default is glow.local. Add “:8080” to reach a node on another port.")
                }

                Section {
                    Picker("Refresh rate", selection: $engine.refreshRate) {
                        ForEach([25, 30, 40, 44], id: \.self) { rate in
                            Text("\(rate) Hz").tag(rate)
                        }
                    }
                } header: {
                    Text("Output")
                } footer: {
                    Text("DMX512 tops out a little above 44 Hz for a full universe. Lower rates are gentler on a busy Wi-Fi network.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.shortVersion)
                    LabeledContent("Protocol", value: "v\(Wire.version)")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .onAppear { manualHost = model.endpoint.source == .manual ? model.endpoint.host : "" }
        }
    }

    /// Accepts "glow.local", "192.168.1.40" or "192.168.1.40:8080". The port
    /// suffix matters for the fake node in tools/, which cannot bind port 80
    /// without root.
    private func applyManualHost() {
        let entry = manualHost.trimmingCharacters(in: .whitespaces)
        guard !entry.isEmpty else { return }

        var host = entry
        var port = 80
        if let separator = entry.lastIndex(of: ":"),
           let parsed = Int(entry[entry.index(after: separator)...]),
           (1...65535).contains(parsed) {
            host = String(entry[..<separator])
            port = parsed
        }

        model.endpoint = ControllerEndpoint(
            host: host,
            port: port,
            displayName: entry,
            source: .manual
        )
    }
}

extension Bundle {
    var shortVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
