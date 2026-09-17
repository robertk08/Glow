import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class Console {
	private(set) var universe = Universe()
	private(set) var link: LinkState = .offline
	private(set) var node: Wire.NodeInfo?
	private(set) var latency: TimeInterval?
	
	var selection: Set<PersistentIdentifier> = []
	
	var master: Double = 1 {
		didSet { needsFullFrame = true }
	}
	
	var blackout = false {
		didSet {
			guard blackout != oldValue else { return }
			needsFullFrame = true
			let value = blackout
			Task { await connection.send(.blackout(value)) }
		}
	}
	
	var endpoint: NodeEndpoint {
		didSet {
			Self.store(endpoint)
			connect()
		}
	}
	
	private let connection = NodeLink()
	private var dimmers: [Dimmer] = []
	private var loop: Task<Void, Never>?
	private var events: Task<Void, Never>?
	private var lastFrame: [UInt8] = []
	private var needsFullFrame = true
	private var lastFullFrame = Date.distantPast
	private var savedLook: [UInt8] = []
	private var lastSave = Date.distantPast
	
	private static let endpointKey = "node.endpoint"
	private static let lookKey = "console.look"
	
	struct Dimmer: Equatable {
		enum Kind: Equatable {
			case linear
			case band(from: UInt8, to: UInt8, open: UInt8?)
		}
		
		var address: DMXAddress
		var kind: Kind
		
		func scale(_ value: UInt8, by master: Double) -> UInt8 {
			guard master < 1 else { return value }
			guard master > 0 else { return 0 }
			
			switch kind {
			case .linear:
				return UInt8((Double(value) * master).rounded())
			case let .band(from, to, open):
				if value < from { return value }
				if value <= to { return from + UInt8((Double(value - from) * master).rounded()) }
				if let open, value >= open { return from + UInt8((Double(to - from) * master).rounded()) }
				return value
			}
		}
	}
	
	init() {
		endpoint = Self.storedEndpoint() ?? .fallback
	}
	
	func start() {
		guard events == nil else { return }
		
		restoreLook()
		
		events = Task { [weak self] in
			guard let self else { return }
			for await event in connection.events {
				switch event {
				case let .state(state):
					link = state
					if state == .connected { needsFullFrame = true }
				case let .status(info):
					node = info
				case let .latency(value):
					latency = value
				}
			}
		}
		
		loop = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(1.0 / 40))
				await self?.tick()
			}
		}
		
		connect()
	}
	
	func connect() {
		needsFullFrame = true
		let target = endpoint
		Task { await connection.connect(to: target) }
	}
	
	func value(at address: DMXAddress) -> UInt8 {
		universe[address]
	}
	
	func set(_ value: UInt8, at address: DMXAddress) {
		universe[address] = value
	}
	
	func set(_ values: [UInt8], at address: DMXAddress) {
		universe.set(values, at: address)
	}
	
	func isSelected(_ fixture: Fixture) -> Bool {
		selection.contains(fixture.persistentModelID)
	}
	
	func isSelected(_ group: FixtureGroup) -> Bool {
		let members = Set(group.members.map(\.persistentModelID))
		return !members.isEmpty && members.isSubset(of: selection)
	}
	
	func toggle(_ fixture: Fixture) {
		if selection.contains(fixture.persistentModelID) {
			selection.remove(fixture.persistentModelID)
		} else {
			selection.insert(fixture.persistentModelID)
		}
	}
	
	func toggle(_ group: FixtureGroup) {
		let members = Set(group.members.map(\.persistentModelID))
		if members.isSubset(of: selection) {
			selection.subtract(members)
		} else {
			selection.formUnion(members)
		}
	}
	
	func control(among fixtures: [Fixture], library: FixtureLibrary) -> FixtureControl {
		FixtureControl(fixtures: fixtures.filter(isSelected), library: library, console: self)
	}
	
	func levels(among fixtures: [Fixture], library: FixtureLibrary) -> [String: [UInt8]] {
		var levels: [String: [UInt8]] = [:]
		
		for fixture in fixtures {
			guard let profile = library.profile(fixture.profileID) else { continue }
			var values: [UInt8] = []
			
			for offset in 0..<profile.channelCount {
				guard let address = fixture.start.offset(by: offset) else { break }
				values.append(universe[address])
			}
			
			levels[fixture.identifier] = values
		}
		
		return levels
	}
	
	func recall(_ look: Look, among fixtures: [Fixture]) {
		let levels = look.fixtureLevels
		
		for fixture in fixtures {
			guard let values = levels[fixture.identifier] else { continue }
			universe.set(values, at: fixture.start)
		}
		
		needsFullFrame = true
	}
	
	func applyPatch(_ fixtures: [Fixture], library: FixtureLibrary) {
		let newDimmers = fixtures.flatMap { FixtureControl(fixture: $0, library: library, console: self)?.dimmers ?? [] }
		guard newDimmers != dimmers else { return }
		dimmers = newDimmers
		needsFullFrame = true
	}
	
	private func output() -> [UInt8] {
		guard !blackout else { return [UInt8](repeating: 0, count: Universe.channelCount) }
		guard master < 1 else { return universe.values }
		
		var values = universe.values
		for dimmer in dimmers {
			let index = dimmer.address.value - 1
			values[index] = dimmer.scale(values[index], by: master)
		}
		return values
	}
	
	private func tick() async {
		saveLook()
		guard link.isConnected else { return }
		
		let frame = output()
		defer { lastFrame = frame }
		
		let stale = Date().timeIntervalSince(lastFullFrame) > 1
		if needsFullFrame || lastFrame.count != frame.count || stale {
			needsFullFrame = false
			lastFullFrame = Date()
			await connection.send(start: DMXAddress(1)!, values: frame)
			return
		}
		
		var first: Int?
		var last: Int?
		for index in frame.indices where lastFrame[index] != frame[index] {
			if first == nil { first = index }
			last = index
		}
		
		guard let first, let last, let start = DMXAddress(first + 1) else { return }
		await connection.send(start: start, values: Array(frame[first...last]))
	}
	
	private func restoreLook() {
		guard let data = UserDefaults.standard.data(forKey: Self.lookKey),
			  data.count == Universe.channelCount
		else { return }
		universe.set([UInt8](data), at: DMXAddress(1)!)
		savedLook = [UInt8](data)
		needsFullFrame = true
	}
	
	private func saveLook() {
		guard universe.values != savedLook, Date().timeIntervalSince(lastSave) > 2 else { return }
		savedLook = universe.values
		lastSave = Date()
		UserDefaults.standard.set(Data(universe.values), forKey: Self.lookKey)
	}
	
	private static func storedEndpoint() -> NodeEndpoint? {
		guard let data = UserDefaults.standard.data(forKey: endpointKey) else { return nil }
		return try? JSONDecoder().decode(NodeEndpoint.self, from: data)
	}
	
	private static func store(_ endpoint: NodeEndpoint) {
		guard let data = try? JSONEncoder().encode(endpoint) else { return }
		UserDefaults.standard.set(data, forKey: endpointKey)
	}
}
