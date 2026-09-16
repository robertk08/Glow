import Foundation

/// A 1-based DMX512 slot number.
///
/// DMX addresses are 1-based on every fixture display, every manual and every
/// console on the market, so they are 1-based here too. The conversion to a
/// 0-based buffer index happens in exactly one place, ``DMXUniverse``, and
/// nowhere else.
nonisolated struct DMXAddress: Hashable, Comparable, Codable, Sendable, RawRepresentable {
    static let first = DMXAddress(rawValue: 1)!
    static let last = DMXAddress(rawValue: DMXUniverse.channelCount)!
    static let valid = 1...DMXUniverse.channelCount

    let rawValue: Int

    init?(rawValue: Int) {
        guard Self.valid.contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// Clamps rather than failing. For UI steppers, where running off the end
    /// of the universe should stop at 512 instead of refusing the edit.
    init(clamping value: Int) {
        rawValue = min(max(value, Self.valid.lowerBound), Self.valid.upperBound)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The address `offset` slots along, or `nil` past the end of the universe.
    func offset(by offset: Int) -> DMXAddress? { DMXAddress(rawValue: rawValue + offset) }
}

extension DMXAddress: CustomStringConvertible {
    var description: String { String(rawValue) }
}
