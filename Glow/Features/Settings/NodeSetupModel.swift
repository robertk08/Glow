import Foundation
import Observation

/// Getting a node onto Wi-Fi, start to finish, without anyone opening the
/// Arduino IDE.
///
/// Four of the five steps are ordinary request-and-reply. The fifth is not, and
/// it is the reason this is a state machine rather than a couple of `await`s in
/// a view.
///
/// `/api/provision` answers *before* the node joins — it has to, because
/// joining is the thing that takes it off the network the reply would have
/// travelled over. So the reply proves only that the node heard us. Success is
/// two further facts, and this model confirms each one with a real request
/// rather than a timer:
///
/// 1. **The phone has left `Glow Setup`** — which we know because `192.168.4.1`
///    has stopped answering.
/// 2. **The node is answering somewhere else** and says it is provisioned.
///
/// Watching those two land is what makes the wait read as progress. Driven by a
/// fixed delay instead, this step is a spinner that looks identical whether it
/// is working or has died, which is precisely the failure PROTOCOL.md warns
/// about.
@Observable @MainActor final class NodeSetupModel {
    /// Why we are here. The paths differ only in where the node is expected to
    /// be when we start looking for it.
    nonisolated enum Mode: Equatable, Identifiable {
        /// A node out of the box. It is making its own access point and is
        /// nowhere else, so the phone has to go to it.
        case newNode

        /// A node already on a network, being moved to another one.
        /// `/api/provision` works on the home network too, so its current
        /// address is worth trying first — that skips the access-point detour
        /// entirely.
        case changeNetwork(currentHost: String?)

        nonisolated var id: String {
            switch self {
            case .newNode: "new"
            case let .changeNetwork(host): "change-\(host ?? "")"
            }
        }
    }

    nonisolated enum Step: Equatable {
        case findingNode
        case choosingNetwork
        case password(ProvisioningClient.Network)
        case joining(ssid: String)
        case finished(name: String, ssid: String)
    }

    /// One line of the waiting checklist.
    nonisolated enum Progress: Equatable {
        case pending, running, done
    }

    /// Where an unprovisioned node answers. Read from ``ProvisioningClient``'s
    /// own default rather than restated, so there is one copy of the address.
    static let setupHost = ProvisioningClient().host

    /// The name of the network the node makes for itself. Fixed by
    /// docs/PROTOCOL.md, not by anything the node tells us, so it is a constant
    /// here and not a field.
    static let setupNetworkName = "Glow Setup"

    // MARK: - State

    private(set) var mode: Mode = .newNode
    private(set) var step: Step = .findingNode

    /// What the node said about itself once we could reach it.
    private(set) var info: ProvisioningClient.Info?

    /// Where the node is answering: the setup access point at first, or the
    /// home network when an already-configured node is being moved.
    private(set) var host = NodeSetupModel.setupHost

    private(set) var networks: [ProvisioningClient.Network] = []
    private(set) var isScanning = false

    /// Why the scan came back empty-handed. Not fatal: a node on the home
    /// network is only obliged to answer `/api/provision` and `/api/forget`
    /// there, so a refused scan is a reason to offer manual entry rather than
    /// a dead end.
    private(set) var scanFailure: String?

    /// How many times we have swept the candidate addresses without an answer.
    /// The view uses this to decide when to stop saying "looking" and start
    /// giving instructions.
    private(set) var searchPasses = 0

    private(set) var handover: Progress = .pending
    private(set) var phoneMoved: Progress = .pending
    private(set) var nodeFound: Progress = .pending
    private(set) var secondsWaiting = 0

    /// Set once the wait has run past its patience. Deliberately not called
    /// "failed": the node may have joined perfectly and mDNS may simply be
    /// slow, so this offers waiting longer as a first-class choice.
    private(set) var isTakingLong = false

    /// The last thing that went wrong, in words fit to show someone. Never
    /// contains a password.
    private(set) var failure: String?

    private var chosenNetwork: ProvisioningClient.Network?
    private var discovery: NodeDiscovery?
    private var commit: ((ControllerEndpoint) -> Void)?
    private var task: Task<Void, Never>?
    private var patience = NodeSetupModel.initialPatience

    /// Seconds of silence before offering a way out. Generous on purpose: a
    /// node joining, DHCP handing out a lease, the phone rejoining and mDNS
    /// propagating are four separate waits stacked end to end.
    private static let initialPatience = 45

    /// True while the node either has the credentials or is about to. Closing
    /// the sheet here does not undo anything, so the view uses this to stop an
    /// accidental swipe from hiding the only screen explaining what happens
    /// next.
    var isCommitted: Bool {
        if case .joining = step { return true }
        return false
    }

    // MARK: - Lifecycle

    func begin(
        mode: Mode,
        discovery: NodeDiscovery,
        commit: @escaping (ControllerEndpoint) -> Void
    ) {
        guard self.commit == nil else { return } // `.task` can run twice
        self.mode = mode
        self.discovery = discovery
        self.commit = commit
        startOver()
    }

    /// Back to the beginning: used by the Try again button, and by the recovery
    /// path when a node that failed to join has gone back to its access point.
    func startOver() {
        failure = nil
        scanFailure = nil
        networks = []
        chosenNetwork = nil
        info = nil
        searchPasses = 0
        handover = .pending
        phoneMoved = .pending
        nodeFound = .pending
        step = .findingNode
        run { await $0.findNode() }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - Step 1: find a node to talk to

    private func findNode() async {
        var hosts: [String] = []
        if case let .changeNetwork(current) = mode, let current, current != Self.setupHost {
            hosts.append(current)
        }
        hosts.append(Self.setupHost)

        while !Task.isCancelled {
            for candidate in hosts {
                guard let info = await Self.reach(candidate, within: 4) else { continue }
                host = candidate
                self.info = info
                step = .choosingNetwork
                await scan()
                return
            }
            searchPasses += 1
            try? await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: - Step 2: ask the node what it can see

    func rescan() {
        run { await $0.scan() }
    }

    private func scan() async {
        isScanning = true
        scanFailure = nil
        defer { isScanning = false }

        do {
            networks = try await ProvisioningClient(host: host).scan()
        } catch {
            networks = []
            // Deliberately not the client's own message. `Failure.unreachable`
            // reads "check you're connected to Glow Setup", which is wrong
            // advice for a node being re-pointed from the home network — the
            // very case where a refused scan is most likely.
            scanFailure = "The node didn't send a list of networks. Try scanning again, or type the name in yourself."
        }
    }

    // MARK: - Step 3: credentials

    func select(_ network: ProvisioningClient.Network) {
        chosenNetwork = network
        failure = nil

        // An open network has nothing to ask for, and a password field with
        // nothing to type in it is a step that only exists to be tapped past.
        if network.secure {
            step = .password(network)
        } else {
            join(ssid: network.ssid, password: "")
        }
    }

    /// A network the node did not list. Hidden SSIDs do not show up in a scan,
    /// and neither does a network that was simply out of range of the node at
    /// the moment it looked.
    func selectHiddenNetwork(ssid: String) {
        select(ProvisioningClient.Network(ssid: ssid, rssi: 0, secure: true, channel: nil))
    }

    /// Hands the credentials over and then waits for the node to reappear.
    ///
    /// `password` is passed straight through to the node and is never stored on
    /// this object, written to disk, or put in a log line or an error message.
    /// The field it came from is cleared as soon as this returns.
    func join(ssid: String, password: String) {
        step = .joining(ssid: ssid)
        failure = nil
        handover = .running
        phoneMoved = .pending
        nodeFound = .pending
        secondsWaiting = 0
        isTakingLong = false
        patience = Self.initialPatience

        run { model in
            do {
                try await ProvisioningClient(host: model.host)
                    .provision(ssid: ssid, password: password)
            } catch {
                model.handover = .pending
                model.failure = error.localizedDescription
                // Back to the field, not to the start: the node is still
                // reachable and only the password was wrong.
                model.step = model.chosenNetwork.map(Step.password) ?? .choosingNetwork
                return
            }
            model.handover = .done
            model.phoneMoved = .running
            await model.waitForNode(ssid: ssid)
        }
    }

    // MARK: - Step 4: wait for it to come back somewhere else

    /// Keeps looking rather than treating the deadline as a verdict.
    func keepWaiting() {
        patience += Self.initialPatience
        isTakingLong = false
    }

    private func waitForNode(ssid: String) async {
        // The browser has been staring at the setup access point, where there
        // is nothing to find. Starting it again points it at whatever network
        // the phone lands on next.
        discovery?.stop()
        discovery?.start()

        let started = Date()

        while !Task.isCancelled {
            if phoneMoved != .done {
                // The setup access point going quiet is the phone having left
                // it — the node drops the access point the moment it joins, so
                // there is nothing left to answer.
                if await Self.reach(Self.setupHost, within: 3) == nil {
                    phoneMoved = .done
                    nodeFound = .running
                }
            }

            if phoneMoved == .done, let endpoint = await findOnHomeNetwork() {
                nodeFound = .done
                commit?(endpoint)
                step = .finished(name: endpoint.displayName, ssid: ssid)
                return
            }

            secondsWaiting = Int(Date().timeIntervalSince(started))
            isTakingLong = secondsWaiting >= patience
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// The node, found on the network it was just sent to.
    ///
    /// `isProvisioned` is what makes this proof rather than a guess: a node
    /// that failed to join is back on its access point and answering
    /// `unprovisioned`, and would otherwise look like success to anything that
    /// only checked whether *something* replied.
    private func findOnHomeNetwork() async -> ControllerEndpoint? {
        for candidate in homeCandidates() {
            guard let info = await Self.reach(candidate.host, within: 3), info.isProvisioned else {
                continue
            }
            return ControllerEndpoint(
                host: candidate.host,
                port: candidate.port,
                displayName: info.name.isEmpty ? candidate.displayName : info.name,
                source: candidate.source
            )
        }
        return nil
    }

    /// Everywhere the node might have landed: whatever Bonjour has found, plus
    /// `glow.local`, which the firmware registers and which therefore works
    /// before any browsing has succeeded.
    private func homeCandidates() -> [ControllerEndpoint] {
        var seen: Set<String> = []
        var candidates: [ControllerEndpoint] = []

        for endpoint in (discovery?.endpoints ?? []) + [.defaultNode] {
            // The setup address answering means the phone never moved, which is
            // the opposite of what is being looked for here.
            guard endpoint.host != Self.setupHost, seen.insert(endpoint.id).inserted else {
                continue
            }
            candidates.append(endpoint)
        }
        return candidates
    }

    // MARK: - Plumbing

    private func run(_ work: @escaping @MainActor (NodeSetupModel) async -> Void) {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await work(self)
        }
    }

    /// Asks one address whether a node is there, giving up after `seconds`.
    ///
    /// ``ProvisioningClient`` allows twenty seconds because `/api/scan` needs
    /// them. A liveness check on that budget would leave the waiting screen
    /// frozen for a third of a minute per address, so the request races a
    /// sleep and loses.
    nonisolated private static func reach(
        _ host: String,
        within seconds: Double
    ) async -> ProvisioningClient.Info? {
        await withTaskGroup(of: ProvisioningClient.Info?.self) { group in
            group.addTask { try? await ProvisioningClient(host: host).info() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
