import SwiftUI

/// Settings, in five parts, because two different people open this screen.
///
/// One of them has a light that has stopped responding and wants the node
/// first: what it is called, whether it is connected, and a way to get it back.
/// The other has a box still in its packaging and wants the second section and
/// nothing else. Everything that is only interesting once something has gone
/// wrong — round-trip time, firmware build, the last error the node sent — is
/// one tap down in Diagnostics, where it cannot make the first screen look like
/// an instrument panel.
///
/// Footers say why a control is here rather than repeating its name. A footer
/// that restates the label is a row and a half of wasted screen.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var setupMode: NodeSetupModel.Mode?
    @State private var isShowingGuide = false

    var body: some View {
        @Bindable var engine = model.engine

        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        NodeSettingsView()
                    } label: {
                        NodeSummaryRow()
                    }
                } footer: {
                    Text("Glow is the desk and the node is the output. Every move you make goes straight to it over Wi-Fi, so your iPhone and the node have to be on the same network.")
                }

                Section {
                    Button("Set up a new node", systemImage: "shippingbox") {
                        setupMode = .newNode
                    }
                    Button("Change the node's Wi-Fi network", systemImage: "wifi") {
                        setupMode = .changeNetwork(currentHost: model.endpoint.host)
                    }
                } header: {
                    Text("Set up")
                } footer: {
                    Text("The node has no screen and no buttons, so everything it needs to know — including which Wi-Fi network to join — is entered here. You never have to plug it into a computer.")
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
                    Text("How many times a second the node re-sends the whole rig to the lights. DMX512 tops out a little above 44 Hz for a full universe. Drop it if fades look uneven on a busy Wi-Fi network — the lights hold their last value between frames, so a lower rate costs smoothness rather than brightness.")
                }

                Section {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnostics", systemImage: "waveform.path")
                    }
                } footer: {
                    Text("Response time, firmware version, how long the node has been running, and the last thing it complained about. Worth opening when a light is not doing what you asked and you want to know whether the app or the rig is at fault.")
                }

                Section {
                    Button("Welcome guide", systemImage: "questionmark.circle") {
                        isShowingGuide = true
                    }
                    LabeledContent("Glow version", value: Bundle.main.shortVersion)
                    LabeledContent("Wire protocol", value: "v\(Wire.version)")
                } header: {
                    Text("About")
                } footer: {
                    Text("The guide is the same short explanation Glow shows the first time it opens: what the box is, what a fixture is, and what an address does.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
        .sheet(item: $setupMode) { mode in
            NodeSetupView(mode: mode)
        }
        .sheet(isPresented: $isShowingGuide) {
            OnboardingView()
        }
    }
}

/// The row at the top: which node, and whether Glow is talking to it.
///
/// Laid out like the Wi-Fi row in Settings — name on the left, current state on
/// the right — because that is the question being asked and it is the answer
/// people already know how to read.
private struct NodeSummaryRow: View {
    @Environment(AppModel.self) private var model

    private var name: String {
        model.engine.nodeStatus?.name ?? model.endpoint.displayName
    }

    var body: some View {
        LabeledContent {
            ConnectionStatusView()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(model.endpoint.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension Bundle {
    var shortVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
