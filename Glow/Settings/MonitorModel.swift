import Observation
import SwiftUI

@Observable @MainActor
final class MonitorModel {
	var patchedOnly = false
	private(set) var adjusting: Int?
	private(set) var values = [UInt8](repeating: 0, count: Universe.channelCount)
	
	private var poll: Task<Void, Never>?
	private var armed: Int?
	private var origin: UInt8 = 0
	private var written: UInt8 = 0
	
	func watch(_ console: Console) {
		guard poll == nil else { return }
		
		poll = Task { [weak self] in
			while !Task.isCancelled {
				let snapshot = console.universe.values
				if snapshot != self?.values { self?.values = snapshot }
				try? await Task.sleep(for: .seconds(0.1))
			}
		}
	}
	
	func stop() {
		poll?.cancel()
		poll = nil
	}
	
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
	
	func commit() {
		armed = nil
		adjusting = nil
	}
	
	func adjust(_ address: Int, by translation: CGSize, console: Console) {
		guard armed == address, let target = DMXAddress(address) else { return }
		let travel = abs(translation.width) > 60 ? 6.0 : 1.5
		let value = UInt8(min(max(Double(origin) - translation.height / travel, 0), 255).rounded())
		guard value != written else { return }
		written = value
		adjusting = address
		console.set(value, at: target)
	}
	
	func border(_ address: Int, owned: Bool, value: UInt8) -> Color {
		if adjusting == address { return .accentColor }
		if owned { return .accentColor.opacity(0.4) }
		return value == 0 ? .clear : .orange
	}
	
}
