import SwiftUI

struct SettingsView: View {
    @Environment(Console.self) private var console
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        NodeView()
                    } label: {
                        LabeledContent {
                            Text(status)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Controller", systemImage: "app.connected.to.app.below.fill")
                        }
                    }
                } footer: {
                    Text("Glow sends to the controller over Wi-Fi. Your iPhone and the controller have to be on the same network.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.version)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button(role: .close) { dismiss() }
            }
        }
    }

    private var status: String {
        switch console.link {
        case .connected: console.node?.name ?? "Connected"
        case .connecting: "Connecting"
        case .retrying: "Reconnecting"
        case .offline: "Not connected"
        }
    }
}

extension Bundle {
    var version: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
