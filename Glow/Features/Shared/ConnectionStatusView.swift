import SwiftUI

/// The connection indicator. Present on every screen, because a lighting
/// console that has quietly stopped talking to the rig looks exactly like one
/// that is working until you move a fader.
struct ConnectionStatusView: View {
    @Environment(AppModel.self) private var model
    var compact = false

    private var state: ConnectionState { model.engine.connection }

    var body: some View {
        Label {
            if !compact {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .contentTransition(.numericText())
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: isBusy)
        }
        .labelStyle(.titleAndIcon)
        .animation(.default, value: state)
        .accessibilityLabel(Text(title))
    }

    private var title: String {
        switch state {
        case .idle: "Not connected"
        case .connecting: "Connecting…"
        case .connected:
            if let latency = model.engine.roundTrip {
                "Connected · \(Int(latency * 1000)) ms"
            } else {
                "Connected"
            }
        case let .waitingToRetry(_, seconds): "Reconnecting in \(seconds)s"
        case .failed: "Connection failed"
        }
    }

    private var symbol: String {
        switch state {
        case .connected: "wifi"
        case .connecting: "wifi.exclamationmark"
        case .waitingToRetry: "wifi.exclamationmark"
        case .idle, .failed: "wifi.slash"
        }
    }

    private var tint: Color {
        switch state {
        case .connected: .green
        case .connecting, .waitingToRetry: .orange
        case .idle, .failed: .red
        }
    }

    private var isBusy: Bool {
        switch state {
        case .connecting, .waitingToRetry: true
        default: false
        }
    }
}
