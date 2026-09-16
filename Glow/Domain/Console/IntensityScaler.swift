import Foundation

/// How the grand master is allowed to touch one address.
///
/// The master is an output stage, so it has to know what each byte *means*
/// before it scales it. A dedicated dimmer just multiplies. A combined
/// dimmer/strobe channel has to be remapped into its dimming band, because
/// multiplying 255 by 0.6 on one of those lands on 153 — which on this class
/// of fixture is not "a bit dimmer", it is a strobe.
nonisolated struct IntensityScaler: Sendable, Equatable, Hashable {
    nonisolated enum Kind: Sendable, Equatable, Hashable {
        case linear
        case band(from: UInt8, to: UInt8, openFrom: UInt8?)
    }

    var address: DMXAddress
    var kind: Kind

    func scale(_ value: UInt8, by master: Double) -> UInt8 {
        guard master < 1 else { return value }
        guard master > 0 else { return 0 }

        switch kind {
        case .linear:
            return UInt8((Double(value) * master).rounded())

        case let .band(from, to, openFrom):
            let span = Double(to - from)

            if value < from {
                return value // already closed
            }
            if value <= to {
                return from + UInt8((Double(value - from) * master).rounded())
            }
            if let openFrom, value >= openFrom {
                // Wide open counts as full, so scale the whole band.
                return from + UInt8((span * master).rounded())
            }
            // Between the dimming band and open is the strobe band. Dimming a
            // strobe is not something this fixture can do, and quietly turning
            // a strobe into a dim look would be worse than leaving it.
            return value
        }
    }
}
