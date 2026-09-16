import Foundation

/// The 512 channel values that define the current look.
///
/// This is the single source of truth for output. Fixtures do not hold their
/// own copies of anything: a patched fixture is a profile plus a start
/// address, and its controls read and write through to this buffer. That
/// keeps the raw channel monitor and the fixture UI from ever disagreeing,
/// because there is only one set of numbers.
nonisolated struct DMXUniverse: Sendable, Equatable {
    static let channelCount = 512

    private(set) var values: [UInt8]

    /// The span touched since the last ``clearDirty()``, so the send loop can
    /// transmit only what changed instead of 512 bytes per tick.
    private(set) var dirty: ClosedRange<Int>?

    init() {
        values = [UInt8](repeating: 0, count: Self.channelCount)
    }

    subscript(address: DMXAddress) -> UInt8 {
        get { values[address.rawValue - 1] }
        set { set(newValue, at: address) }
    }

    mutating func set(_ value: UInt8, at address: DMXAddress) {
        let index = address.rawValue - 1
        guard values[index] != value else { return }
        values[index] = value
        markDirty(index)
    }

    /// Writes consecutive values starting at `address`, stopping at the end of
    /// the universe. Used when applying a fixture's defaults or a scene.
    mutating func set(contentsOf newValues: [UInt8], startingAt address: DMXAddress) {
        for (offset, value) in newValues.enumerated() {
            guard let target = address.offset(by: offset) else { break }
            set(value, at: target)
        }
    }

    mutating func setAll(_ value: UInt8) {
        for index in values.indices where values[index] != value {
            values[index] = value
            markDirty(index)
        }
    }

    /// The channel values a fixture at `address` occupies, zero-padded if the
    /// fixture runs off the end of the universe.
    func values(from address: DMXAddress, count: Int) -> [UInt8] {
        (0..<count).map { offset in
            address.offset(by: offset).map { self[$0] } ?? 0
        }
    }

    mutating func clearDirty() { dirty = nil }

    private mutating func markDirty(_ index: Int) {
        if let current = dirty {
            dirty = min(current.lowerBound, index)...max(current.upperBound, index)
        } else {
            dirty = index...index
        }
    }
}
