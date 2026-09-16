import SwiftUI

struct NodeView: View {
    @Environment(Console.self) private var console
    @Environment(NodeDiscovery.self) private var discovery

    @State private var isSettingUp = false
    @State private var manualHost = ""
    @State private var isForgetting = false

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: status)

                if let node = console.node {
                    LabeledContent("Name", value: node.name)
                }

                LabeledContent("Address", value: console.endpoint.host)
            }

            Section {
                Button("Identify") {
                    console.identify()
                }
                .disabled(!console.link.isConnected)

                Button("Change Wi-Fi Network") {
                    isSettingUp = true
                }
            } footer: {
                Text("Identify flashes the lights so you can tell which controller you are talking to.")
            }

            if !discovery.endpoints.isEmpty {
                Section("On This Network") {
                    ForEach(discovery.endpoints) { endpoint in
                        Button {
                            console.endpoint = endpoint
                        } label: {
                            LabeledContent {
                                if endpoint.id == console.endpoint.id {
                                    Image(systemName: "checkmark")
                                }
                            } label: {
                                Text(endpoint.name)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                TextField("Address", text: $manualHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(applyManualHost)
            } header: {
                Text("Connect By Address")
            } footer: {
                Text("Only needed if the controller does not show up by itself.")
            }
        }
        .navigationTitle("Controller")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isSettingUp) {
            NodeSetupView()
        }
        .task {
            discovery.start()
            manualHost = console.endpoint.host
        }
        .onDisappear { discovery.stop() }
    }

    private var status: String {
        switch console.link {
        case .connected:
            if let latency = console.latency {
                "Connected · \(Int(latency * 1000)) ms"
            } else {
                "Connected"
            }
        case .connecting: "Connecting"
        case let .retrying(seconds): "Reconnecting in \(seconds)s"
        case .offline: "Not connected"
        }
    }

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

        console.endpoint = NodeEndpoint(host: host, port: port, name: entry)
    }
}
