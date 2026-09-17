import Observation
import SwiftUI

@Observable @MainActor
final class MonitorModel {
	var patchedOnly = false
	private(set) var armed: Int?
	
	private var origin: UInt8 = 0
	private var written: UInt8 = 0
	
	func owners(among fixtures: [Fixture], library: FixtureLibrary) -> Set<Int> {
		var found: Set<Int> = []
		
		for fixture in fixtures {
			found.formUnion(fixture.range(library.profile(fixture.profileID)))
		}
		
		return found
	}
	
	func blocks(owned: Set<Int>) -> [[Int]] {
		let addresses = patchedOnly ? DMXAddress.range.filter(owned.contains) : Array(DMXAddress.range)
		return stride(from: 0, to: addresses.count, by: 32).map { Array(addresses[$0..<min($0 + 32, addresses.count)]) }
	}
	
	func arm(_ address: Int, console: Console) {
		guard armed != address, let target = DMXAddress(address) else { return }
		armed = address
		origin = console.value(at: target)
		written = origin
	}
	
	func adjust(_ address: Int, by translation: CGSize, console: Console) {
		guard armed == address, let target = DMXAddress(address) else { return }
		let travel = abs(translation.width) > 60 ? 6.0 : 1.5
		let value = UInt8(min(max(Double(origin) - translation.height / travel, 0), 255).rounded())
		guard value != written else { return }
		written = value
		console.set(value, at: target)
	}
	
	func commit() {
		armed = nil
	}
	
	func border(_ address: Int, owned: Bool, value: UInt8) -> Color {
		if armed == address { return .accentColor }
		if owned { return .accentColor.opacity(0.4) }
		return value == 0 ? .clear : .orange
	}
	
	func nudge(_ address: Int, direction: AccessibilityAdjustmentDirection, console: Console) {
		guard let target = DMXAddress(address) else { return }
		let step = direction == .increment ? 1 : -1
		console.set(UInt8(min(max(Int(console.value(at: target)) + step, 0), 255)), at: target)
	}
}
