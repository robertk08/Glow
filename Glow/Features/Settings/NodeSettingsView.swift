import SwiftUI

/// Which node Glow is talking to, and how to change that.
///
/// Pushed rather than sitting on the first screen: on a rig with one node this
/// is all settled automatically over Bonjour and nobody ever needs to look at
/// it. It matters when there are two boxes, or when the network is one of the
/// many that quietly drop multicast.
struct NodeSettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var manualHost = ""
    @State private var isConfirmingForget = false
    @State private var forgetFailure: String?
    @State private var isForgetting = false
    @State private var hasForgotten = false

    private var isConnected: Bool { model.engine.connection.isConnected }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") { ConnectionStatusView() }
                LabeledContent("Name", value: model.engine.nodeStatus?.name ?? model.endpoint.displayName)
                LabeledContent("Address", value: addressText)
            } header: {
                Text("Connected to")
            } footer: {
                if case let .failed(reason) = model.engine.connection {
                    Text(reason).foregroundStyle(.red)
                } else {
                    Text("The node holds whatever look it was last sent, so a dropped connection leaves the lights where they were rather than blacking the stage out.")
                }
            }

            Section {
                Button("Reconnect now", systemImage: "arrow.clockwise") {
                    model.engine.retry()
                }
                Button("Identify", systemImage: "light.beacon.max") {
                    model.engine.identify()
                }
                .disabled(!isConnected)
            } footer: {
                Text("Identify flashes the light on the node itself. Use it when two boxes are within reach and you want to know which one you are about to unplug.")
            }

            Section {
                if model.discovery.endpoints.isEmpty {
                    HStack {
                        Text("Looking for nodes…").foregroundStyle(.secondary)
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                } else {
                    ForEach(model.discovery.endpoints) { endpoint in
                        Button {
                            model.endpoint = endpoint
                        } label: {
                            DiscoveredNodeRow(
                                endpoint: endpoint,
                                isCurrent: endpoint.id == model.endpoint.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Nodes on this network")
            } footer: {
                if model.discovery.permissionDenied {
                    Text("Glow can't search the local network. Turn on Local Network for Glow in Settings › Privacy & Security — without it the app can only reach a node whose address you type in below.")
                        .foregroundStyle(.orange)
                } else {
                    Text("Nodes announce themselves and Glow listens. Guest networks and some mesh routers block that announcement, which is why the box below exists.")
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
                Text("Connect by address")
            } footer: {
                Text("glow.local is the name every node answers to. A numeric address works too, and adding “:8080” reaches a node listening on another port.")
            }

            Section {
                Button("Make the node forget this network", systemImage: "trash", role: .destructive) {
                    isConfirmingForget = true
                }
                .disabled(!isConnected || isForgetting)

                if isForgetting {
                    ProgressView()
                }
                if hasForgotten {
                    // The connection dropping is the only other evidence this
                    // worked, and a connection dropping is also what a failed
                    // request looks like.
                    Label(
                        "Done. The node is restarting and will make its own “\(NodeSetupModel.setupNetworkName)” network in a moment.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if let forgetFailure {
                    Text(forgetFailure).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                Text("The node drops your Wi-Fi details, restarts, and goes back to making its own “\(NodeSetupModel.setupNetworkName)” network. Nothing about your rig is lost — the patch and the fixtures live in this app — but the node can't be controlled again until it has been set up.")
            }
        }
        .navigationTitle("Node")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manualHost = model.endpoint.source == .manual ? model.endpoint.host : ""
        }
        .confirmationDialog(
            "Make the node forget this network?",
            isPresented: $isConfirmingForget,
            titleVisibility: .visible
        ) {
            Button("Forget network", role: .destructive) { forget() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to set it up again before it can be controlled.")
        }
    }

    private var addressText: String {
        model.endpoint.port == 80
            ? model.endpoint.host
            : "\(model.endpoint.host):\(model.endpoint.port)"
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

    private func forget() {
        let host = model.endpoint.host
        isForgetting = true
        forgetFailure = nil
        hasForgotten = false

        Task {
            defer { isForgetting = false }
            do {
                try await ProvisioningClient(host: host).forget()
                hasForgotten = true
            } catch {
                forgetFailure = error.localizedDescription
            }
        }
    }
}

private struct DiscoveredNodeRow: View {
    let endpoint: ControllerEndpoint
    let isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(endpoint.displayName)
                Text(endpoint.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}
