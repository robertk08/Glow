import Foundation
import Network
import os
import Observation

/// Finds Glow nodes on the local network over Bonjour.
///
/// Browsing gives service *instance* names, which are not hostnames, so a
/// chosen service is resolved to a concrete host and port before it can be
/// turned into a WebSocket URL. The alternative — assuming the instance name
/// matches the mDNS hostname — is true right up until someone runs two nodes
/// and the second one gets renamed out from under them.
@Observable @MainActor final class NodeDiscovery {
    private(set) var endpoints: [ControllerEndpoint] = []
    private(set) var isBrowsing = false

    /// Set when browsing fails because local network permission was refused,
    /// which is otherwise indistinguishable from "no nodes here".
    private(set) var permissionDenied = false

    private var browser: NWBrowser?
    private var services: [String: NWEndpoint] = [:]

    static let serviceType = "_glow._tcp"

    func start() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isBrowsing = true
                    self.permissionDenied = false
                case let .failed(error):
                    self.isBrowsing = false
                    // NWError surfaces a refused local network prompt as a
                    // policy failure rather than anything more specific.
                    self.permissionDenied = "\(error)".localizedCaseInsensitiveContains("policy")
                case .cancelled:
                    self.isBrowsing = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                await self?.update(with: results)
            }
        }

        self.browser = browser
        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    private func update(with results: Set<NWBrowser.Result>) async {
        var found: [ControllerEndpoint] = []

        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            services[name] = result.endpoint

            if let resolved = await Self.resolve(result.endpoint) {
                found.append(
                    ControllerEndpoint(
                        host: resolved.host,
                        port: resolved.port,
                        displayName: name,
                        source: .discovered
                    )
                )
            }
        }

        endpoints = found.sorted { $0.displayName < $1.displayName }
    }

    /// Opens a throwaway TCP connection purely to learn the address Bonjour
    /// resolved to, then drops it.
    private static func resolve(_ endpoint: NWEndpoint) async -> (host: String, port: Int)? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let hasResumed = OSAllocatedUnfairLock(initialState: false)

            @Sendable func finish(_ value: (host: String, port: Int)?) {
                let shouldResume = hasResumed.withLock { resumed in
                    guard !resumed else { return false }
                    resumed = true
                    return true
                }
                guard shouldResume else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint else {
                        finish(nil)
                        return
                    }
                    let hostString = switch host {
                    case let .name(name, _): name
                    case let .ipv4(address): "\(address)".components(separatedBy: "%").first ?? "\(address)"
                    case let .ipv6(address): "\(address)".components(separatedBy: "%").first ?? "\(address)"
                    @unknown default: ""
                    }
                    finish(hostString.isEmpty ? nil : (hostString, Int(port.rawValue)))
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))

            Task {
                try? await Task.sleep(for: .seconds(4))
                finish(nil)
            }
        }
    }
}
