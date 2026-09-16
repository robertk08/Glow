import Foundation

nonisolated struct DMXAddress: Hashable, Comparable, Codable, Sendable {
    static let range = 1...512

    let value: Int

    init?(_ value: Int) {
        guard Self.range.contains(value) else { return nil }
        self.value = value
    }

    init(clamping value: Int) {
        self.value = min(max(value, Self.range.lowerBound), Self.range.upperBound)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    func offset(by offset: Int) -> DMXAddress? { DMXAddress(value + offset) }
}

nonisolated struct Universe: Sendable, Equatable {
    static let channelCount = 512

    private(set) var values = [UInt8](repeating: 0, count: Universe.channelCount)

    subscript(address: DMXAddress) -> UInt8 {
        get { values[address.value - 1] }
        set { values[address.value - 1] = newValue }
    }

    mutating func set(_ newValues: [UInt8], at address: DMXAddress) {
        for (offset, value) in newValues.enumerated() {
            guard let target = address.offset(by: offset) else { return }
            self[target] = value
        }
    }

    func values(from address: DMXAddress, count: Int) -> [UInt8] {
        (0..<count).map { address.offset(by: $0).map { self[$0] } ?? 0 }
    }
}
