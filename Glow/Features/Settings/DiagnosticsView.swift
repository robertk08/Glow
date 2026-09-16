import SwiftUI

/// The numbers, for when something is wrong.
///
/// Split from the rest of Settings because none of it is actionable: there is
/// no control on this screen. It exists to answer one question — is the app
/// sending, and is the node hearing — and every figure on it comes from the
/// node rather than from the app's own idea of what it did.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    private var status: Wire.NodeStatus? { model.engine.nodeStatus }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") { ConnectionStatusView() }
                LabeledContent("Response time", value: responseTime)
                LabeledContent("Glow is sending", value: "\(model.engine.refreshRate) Hz")
            } header: {
                Text("Link")
            } footer: {
                Text("Response time is how long a heartbeat takes to reach the node and come back. Under about 50 ms a fader feels attached to the light. A figure that climbs while you work is almost always Wi-Fi congestion rather than a fault in either end.")
            }

            Section {
                if let status {
                    LabeledContent("Firmware", value: status.firmware)
                    LabeledContent("Serial number", value: Self.grouped(status.id))
                    LabeledContent("Running for", value: Self.uptime(status.uptime))
                    LabeledContent("Node is sending", value: "\(status.hz) Hz")
                    LabeledContent("Blackout", value: status.blackout ? "On" : "Off")

                    if status.hz != model.engine.refreshRate {
                        Label(
                            "The node is clocking \(status.hz) Hz, not the \(model.engine.refreshRate) Hz Glow asked for. It either refused the change or hasn't been told yet.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                } else {
                    Text("Nothing yet. The node sends this when Glow connects.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("What the node says")
            } footer: {
                Text("Reported by the node itself rather than assumed by the app, so a disagreement between these two sections is a real clue. Running for counts from the last time it had power — a figure that keeps starting over means it is rebooting.")
            }

            Section {
                if let error = model.engine.lastNodeError {
                    Text(error)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                } else {
                    Text("Nothing reported.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Last problem reported")
            } footer: {
                Text("The node refuses a frame it doesn't understand instead of guessing what was meant, and says which one. An empty line here is the normal state.")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var responseTime: String {
        guard let latency = model.engine.roundTrip else { return "—" }
        return "\(Int(latency * 1000)) ms"
    }

    /// The node's id is the station MAC as twelve undifferentiated hex
    /// characters. That is the right thing on the wire and unreadable on a
    /// screen, so it is grouped for display only — the value itself is
    /// untouched.
    private static func grouped(_ id: String) -> String {
        guard id.count == 12 else { return id.isEmpty ? "—" : id }
        return stride(from: 0, to: 12, by: 2)
            .map { offset -> String in
                let start = id.index(id.startIndex, offsetBy: offset)
                let end = id.index(start, offsetBy: 2)
                return String(id[start..<end])
            }
            .joined(separator: ":")
    }

    private static func uptime(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes, .seconds], maximumUnitCount: 2)
        )
    }
}
