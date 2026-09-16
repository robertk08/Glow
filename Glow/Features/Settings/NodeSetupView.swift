import SwiftUI
import UIKit

/// The whole setup conversation, presented as a sheet.
///
/// One screen at a time, each with one thing to do. The person has to leave the
/// app in the middle of it — iOS will not let an app join a network on someone's
/// behalf without an entitlement Glow does not have — so every screen has to be
/// worth coming back to.
struct NodeSetupView: View {
    let mode: NodeSetupModel.Mode

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var setup = NodeSetupModel()

    var body: some View {
        NavigationStack {
            Group {
                switch setup.step {
                case .findingNode:
                    FindNodeStep(setup: setup)
                case .choosingNetwork:
                    ChooseNetworkStep(setup: setup)
                case let .password(network):
                    PasswordStep(setup: setup, network: network)
                case let .joining(ssid):
                    JoiningStep(setup: setup, ssid: ssid)
                case let .finished(name, ssid):
                    FinishedStep(name: name, ssid: ssid) { dismiss() }
                }
            }
            .animation(.default, value: setup.step)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let label = closeButtonTitle {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(label) {
                            setup.cancel()
                            dismiss()
                        }
                    }
                }
            }
        }
        // Once the node has the credentials, closing changes nothing but hides
        // the only screen that says what is about to happen. A stray swipe
        // should not be able to do that.
        .interactiveDismissDisabled(setup.isCommitted)
        .task {
            setup.begin(mode: mode, discovery: model.discovery) { endpoint in
                model.endpoint = endpoint
            }
        }
    }

    private var title: String {
        switch setup.step {
        case .findingNode: "Set up"
        case .choosingNetwork: "Choose network"
        case .password: "Password"
        case .joining: "Joining"
        case .finished: "Ready"
        }
    }

    private var closeButtonTitle: String? {
        switch setup.step {
        case .findingNode, .choosingNetwork, .password: "Cancel"
        case .joining: "Close"
        case .finished: nil
        }
    }
}

// MARK: - Step 1: reach the node

private struct FindNodeStep: View {
    let setup: NodeSetupModel

    @Environment(\.openURL) private var openURL

    /// For a new node the instructions are the whole point of the screen. For a
    /// node already on the network they are a fallback, and showing them first
    /// would tell someone to go and do something they very likely need not do.
    private var showsInstructions: Bool {
        setup.mode == .newNode || setup.searchPasses >= 2
    }

    var body: some View {
        SetupStepLayout(
            symbol: "wifi.router",
            title: showsInstructions ? "Join the node's own network" : "Looking for the node",
            message: showsInstructions
                ? "A node that hasn't been set up yet makes a Wi-Fi network of its own, so your iPhone has a way to reach it. It has no password."
                : "Checking whether the node is already somewhere Glow can reach it."
        ) {
            if showsInstructions {
                VStack(alignment: .leading, spacing: 14) {
                    NumberedInstruction(number: 1, text: "Open Settings, then Wi-Fi.")
                    NumberedInstruction(
                        number: 2,
                        text: "Tap “\(NodeSetupModel.setupNetworkName)”."
                    )
                    NumberedInstruction(number: 3, text: "Come back to Glow.")
                }

                Text("Your iPhone will warn that this network has no internet connection. That is expected — the node is not a router. Stay on it until setup has finished.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            WorkingLine(text: "Waiting for the node to answer…")
        } actions: {
            if showsInstructions {
                Button("Open Settings") {
                    // Lands on Glow's own page in Settings; Wi-Fi is one step up
                    // from there. There is no public URL that opens Wi-Fi
                    // directly, and a private one is not worth the review risk.
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Step 2: choose a network

private struct ChooseNetworkStep: View {
    let setup: NodeSetupModel

    @State private var isEnteringHiddenNetwork = false
    @State private var hiddenSSID = ""

    var body: some View {
        List {
            if let info = setup.info {
                Section {
                    Label("Talking to \(info.name)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                }
            }

            Section {
                if setup.isScanning && setup.networks.isEmpty {
                    WorkingLine(text: "Asking the node what it can see…")
                }

                ForEach(setup.networks) { network in
                    Button {
                        setup.select(network)
                    } label: {
                        NetworkRow(network: network)
                    }
                    .buttonStyle(.plain)
                }

                if let failure = setup.scanFailure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Other network…") { isEnteringHiddenNetwork = true }
            } header: {
                Text("Networks the node can see")
            } footer: {
                Text("This is the node's view, not your iPhone's — it is somewhere else in the building and picks up only 2.4 GHz networks. A network that is missing is usually one of those two things. Use Other network for a name that isn't broadcast.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Scan again", systemImage: "arrow.clockwise") { setup.rescan() }
                    .disabled(setup.isScanning)
            }
        }
        .alert("Other network", isPresented: $isEnteringHiddenNetwork) {
            TextField("Network name", text: $hiddenSSID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { hiddenSSID = "" }
            Button("Next") {
                let ssid = hiddenSSID.trimmingCharacters(in: .whitespaces)
                hiddenSSID = ""
                guard !ssid.isEmpty else { return }
                setup.selectHiddenNetwork(ssid: ssid)
            }
        } message: {
            Text("Type the name exactly as your router broadcasts it. Capitals matter.")
        }
    }
}

private struct NetworkRow: View {
    let network: ProvisioningClient.Network

    var body: some View {
        HStack(spacing: 10) {
            Text(network.ssid)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if network.secure {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "wifi", variableValue: Double(network.bars) / 3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: Text {
        Text(
            network.secure
                ? "\(network.ssid), password protected, signal \(network.bars) of 3"
                : "\(network.ssid), open network, signal \(network.bars) of 3"
        )
    }
}

// MARK: - Step 3: the password

private struct PasswordStep: View {
    let setup: NodeSetupModel
    let network: ProvisioningClient.Network

    @State private var password = ""
    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        SetupStepLayout(
            symbol: "lock",
            title: "Password for “\(network.ssid)”",
            message: "The node needs this to join. Glow hands it straight over and keeps no copy of it — not on your iPhone, and not in iCloud."
        ) {
            HStack {
                Group {
                    // No `textContentType`: the saved-passwords keyboard offers
                    // website logins, and the one password wanted here is the
                    // one thing it does not have.
                    if isRevealed {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.join)
                .focused($isFocused)
                .onSubmit(join)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            }
            .textFieldStyle(.roundedBorder)

            if let failure = setup.failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } actions: {
            Button("Join network", action: join)
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
                .disabled(password.isEmpty)
        }
        .onAppear { isFocused = true }
    }

    private func join() {
        guard !password.isEmpty else { return }
        setup.join(ssid: network.ssid, password: password)
        // Gone from this view the instant it has been sent. The model never
        // held it, and now nothing does.
        password = ""
    }
}

// MARK: - Step 4: the wait

private struct JoiningStep: View {
    let setup: NodeSetupModel
    let ssid: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        SetupStepLayout(
            symbol: "wifi",
            title: "Joining “\(ssid)”",
            message: "The node answered before it moved — it had to, because moving is what takes it off the network the answer came over. So Glow goes and looks for it."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ProgressLine(
                    state: setup.handover,
                    text: "Details sent to the node"
                )
                ProgressLine(
                    state: setup.phoneMoved,
                    text: "Your iPhone back on a normal network"
                )
                ProgressLine(
                    state: setup.nodeFound,
                    text: "Node found on “\(ssid)”"
                )
            }

            if setup.phoneMoved != .done && setup.secondsWaiting >= 10 {
                HintBox(
                    symbol: "wifi",
                    text: "Still on “\(NodeSetupModel.setupNetworkName)”? That network has gone now. Open Settings › Wi-Fi and join “\(ssid)”."
                )
            }

            if setup.isTakingLong {
                HintBox(
                    symbol: "exclamationmark.circle",
                    text: "No sign of it yet. It may still be joining — or it may not have managed to, in which case it has gone back to making “\(NodeSetupModel.setupNetworkName)” and you can try again with a different password. Check your iPhone is on “\(ssid)”, because that is where the node now is."
                )
            }
        } actions: {
            if setup.isTakingLong {
                Button("Keep looking") { setup.keepWaiting() }
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)
                Button("Start again") { setup.startOver() }
                    .frame(maxWidth: .infinity)
            } else {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Step 5: done

private struct FinishedStep: View {
    let name: String
    let ssid: String
    let done: () -> Void

    var body: some View {
        SetupStepLayout(
            symbol: "checkmark.circle.fill",
            title: "\(name) is on “\(ssid)”",
            message: "It will find its way back to this network on its own from now on, including after a power cut. Glow is already talking to it."
        ) {
            Text("Next: add your light in Patch, using the address shown on the light itself. Then bring it up on Stage.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } actions: {
            Button("Done", action: done)
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Shared pieces

/// The shape every step takes: one symbol, one plain sentence of what is going
/// on, the detail, and one obvious thing to do.
///
/// A scroll view rather than a centred stack, because these screens are mostly
/// words and at the accessibility text sizes words need somewhere to go.
private struct SetupStepLayout<Content: View, Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 52))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(message)
                        .foregroundStyle(.secondary)
                }

                content
            }
            .padding()
            .readableWidth()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) { actions }
                .padding()
                .readableWidth()
                .background(.bar)
        }
    }
}

/// One numbered thing to do, out in the world rather than in the app.
private struct NumberedInstruction: View {
    let number: Int
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.tint)
        }
        .accessibilityLabel("Step \(number). \(text)")
    }
}

/// A line of the waiting checklist. Three states rather than two, because
/// "not started" and "in progress" answer different questions.
private struct ProgressLine: View {
    let state: NodeSetupModel.Progress
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                switch state {
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                case .running:
                    ProgressView()
                        .controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 22)

            Text(text)
                .foregroundStyle(state == .pending ? .secondary : .primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(text). \(spokenState)"))
    }

    private var spokenState: String {
        switch state {
        case .pending: "Waiting to start"
        case .running: "In progress"
        case .done: "Done"
        }
    }
}

private struct WorkingLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

/// Advice that only appears when it has become relevant. Set apart from the
/// body text because by the time someone reads it they are looking for the one
/// sentence that tells them what to do.
private struct HintBox: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
    }
}

private extension View {
    /// Keeps a column of prose off the far edges of an iPad. Text that runs the
    /// full width of a landscape iPad is measurably harder to read, and these
    /// screens are almost entirely text.
    func readableWidth() -> some View {
        frame(maxWidth: 520).frame(maxWidth: .infinity)
    }
}
