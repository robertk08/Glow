import SwiftUI

struct NodeSetupView: View {
    @Environment(Console.self) private var console
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var step = Step.findController
    @State private var networks: [NodeSetup.Network] = []
    @State private var selected: NodeSetup.Network?
    @State private var password = ""
    @State private var failure: String?

    private enum Step {
        case findController, chooseNetwork, password, joining, done
    }

    private let setup = NodeSetup()

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .findController: findController
                case .chooseNetwork: chooseNetwork
                case .password: passwordEntry
                case .joining: joining
                case .done: done
                }
            }
            .navigationTitle("Wi-Fi Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button(role: .close) { dismiss() }
            }
        }
    }

    private var findController: some View {
        List {
            Section {
                Text("Open Wi-Fi settings and join the network called **Glow Setup**, then come back. Your iPhone will say it has no internet, which is expected.")

                Button("Open Wi-Fi Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            } footer: {
                if let failure {
                    Text(failure)
                } else {
                    Text("Waiting for the controller…")
                }
            }
        }
        .task { await waitForController() }
    }

    private var chooseNetwork: some View {
        List {
            if networks.isEmpty {
                Section {
                    HStack {
                        Text("Looking for networks")
                        Spacer()
                        ProgressView()
                    }
                }
            } else {
                Section {
                    ForEach(networks) { network in
                        Button {
                            selected = network
                            password = ""
                            step = network.secure ? .password : .joining
                            if !network.secure {
                                Task { await join() }
                            }
                        } label: {
                            LabeledContent {
                                HStack(spacing: 6) {
                                    if network.secure {
                                        Image(systemName: "lock.fill")
                                    }
                                    Image(systemName: "wifi", variableValue: Double(network.bars) / 3)
                                }
                                .foregroundStyle(.secondary)
                            } label: {
                                Text(network.ssid)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("These are the networks the controller can see. It only works on 2.4 GHz.")
                }
            }
        }
        .task { await loadNetworks() }
    }

    private var passwordEntry: some View {
        List {
            Section {
                SecureField("Password", text: $password)
                    .submitLabel(.join)
                    .onSubmit { Task { await join() } }
            } header: {
                Text(selected?.ssid ?? "")
            }

            Section {
                Button("Join") {
                    Task { await join() }
                }
                .disabled(password.isEmpty)
            }
        }
    }

    private var joining: some View {
        List {
            Section {
                HStack {
                    Text("Joining \(selected?.ssid ?? "")")
                    Spacer()
                    ProgressView()
                }
            } footer: {
                if let failure {
                    Text(failure)
                } else {
                    Text("The controller leaves its own network now, so your iPhone will drop back to your usual Wi-Fi.")
                }
            }
        }
    }

    private var done: some View {
        ContentUnavailableView {
            Label("Ready", systemImage: "checkmark.circle")
        } description: {
            Text("The controller is on \(selected?.ssid ?? "your network").")
        } actions: {
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func waitForController() async {
        while step == .findController, !Task.isCancelled {
            if (try? await setup.info()) != nil {
                step = .chooseNetwork
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func loadNetworks() async {
        do {
            networks = try await setup.scan()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func join() async {
        step = .joining
        failure = nil

        guard let ssid = selected?.ssid else { return }

        do {
            try await setup.join(ssid: ssid, password: password)
            password = ""
        } catch {
            failure = error.localizedDescription
            return
        }

        for _ in 0..<30 {
            try? await Task.sleep(for: .seconds(2))
            if let info = try? await NodeSetup(host: console.endpoint.host).info(), info.isProvisioned {
                step = .done
                console.connect()
                return
            }
        }

        failure = "Couldn't find the controller afterwards. If it could not join, it goes back to making its own Glow Setup network so you can try again."
    }
}
