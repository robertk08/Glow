import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class Console {
	private(set) var universe = Universe()
	private(set) var link: LinkState = .offline
	private(set) var node: Wire.NodeInfo?
	private(set) var latency: TimeInterval?
	private(set) var notice: Wire.Notice?
	
	let selection = Selection()
	
	var master: Double = 1 {
		didSet {
			outputFrames.startOver()
			guard !isAdopting else { return }
			let level = master
			
			Task {
				await connection.send(.master(level))
			}
		}
	}
	
	var blackout = false {
		didSet {
			guard blackout != oldValue else { return }
			outputFrames.startOver()
			guard !isAdopting else { return }
			let value = blackout
			
			Task {
				await connection.send(.blackout(value))
			}
		}
	}
	
	var endpoint: NodeEndpoint {
		didSet {
			if let data = try? JSONEncoder().encode(endpoint) {
				UserDefaults.standard.set(data, forKey: Self.endpointKey)
			}
			connect()
		}
	}
	
	private(set) var active: Set<Int> = []
	private(set) var resets = 0
	
	private let connection = NodeLink()
	private var dimmers: [Dimmer] = []
	private var loop: Task<Void, Never>?
	private var events: Task<Void, Never>?
	private var sourceFrames = FrameStream()
	private var outputFrames = FrameStream()
	private var isSynced = false
	private var isAdopting = false
	private var hasLoadedPatch = false
	private var notices = 0
	private var patched: Set<Int> = []
	
	private static let endpointKey = "node.endpoint"
	
	init() {
		if let data = UserDefaults.standard.data(forKey: Self.endpointKey), let stored = try? JSONDecoder().decode(NodeEndpoint.self, from: data) {
			endpoint = stored
		} else {
			endpoint = .fallback
		}
	}
	
	func start() {
		guard events == nil else { return }
		
		events = Task { [weak self] in
			guard let self else { return }
			for await event in connection.events {
				switch event {
				case let .state(state):
					link = state
					if state == .connected {
						isSynced = false
						sourceFrames.startOver()
						outputFrames.startOver()
					}
				case let .status(info):
					node = info
					if !info.hasSource { isSynced = true }
				case let .latency(value):
					latency = value
				case let .frame(start, values):
					universe.set(values, at: start)
					sourceFrames.adopt(universe.values)
					outputFrames.startOver()
					isSynced = true
				case let .master(level):
					isAdopting = true
					master = level
					isAdopting = false
				case let .blackout(on):
					isAdopting = true
					blackout = on
					isAdopting = false
				case let .notice(incoming):
					notices += 1
					var stamped = incoming
					stamped.sequence = notices
					notice = stamped
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
		isSynced = false
		sourceFrames.startOver()
		outputFrames.startOver()
		let target = endpoint
		
		Task {
			await connection.connect(to: target)
		}
	}
	
	func value(at address: DMXAddress) -> UInt8 {
		universe[address]
	}
	
	func set(_ value: UInt8, at address: DMXAddress) {
		universe[address] = value
		active.insert(address.value)
	}
	
	func set(_ values: [UInt8], at address: DMXAddress) {
		universe.set(values, at: address)
	}
	
	func isActive(_ address: DMXAddress) -> Bool {
		active.contains(address.value)
	}
	
	func release(_ span: ClosedRange<Int>, only offset: Int? = nil) {
		guard let offset else {
			active.subtract(span)
			return
		}
		
		active.remove(span.lowerBound + offset - 1)
	}
	
	func closeShow() {
		universe = Universe()
		active = []
		dimmers = []
		patched = []
		hasLoadedPatch = false
		selection.clear()
		sourceFrames.startOver()
		outputFrames.startOver()
	}
	
	func reset(among fixtures: [Fixture], library: FixtureLibrary) {
		let chosen = fixtures.filter(selection.contains)
		Programmer(fixtures: chosen.isEmpty ? fixtures : chosen, library: library, console: self).applyDefaults()
		selection.clear()
		resets += 1
	}
	
	func programmer(among fixtures: [Fixture], library: FixtureLibrary) -> Programmer {
		Programmer(fixtures: fixtures.filter(selection.contains), library: library, console: self)
	}
	
	func repatch(_ fixture: Fixture, library: FixtureLibrary, change: (Fixture) -> Void) {
		let old = fixture.range(library.type(fixture.typeID))
		universe.set([UInt8](repeating: 0, count: old.count), at: DMXAddress(clamping: old.lowerBound))
		release(old)
		change(fixture)
		
		if let type = library.type(fixture.typeID) {
			universe.set(type.defaults, at: fixture.start)
			release(fixture.range(type))
		}
		
		outputFrames.startOver()
	}
	
	func remove(_ fixture: Fixture, context: ModelContext, library: FixtureLibrary) {
		let width = max(1, library.type(fixture.typeID)?.channelCount ?? 1)
		universe.set([UInt8](repeating: 0, count: width), at: fixture.start)
		release(fixture.range(library.type(fixture.typeID)))
		outputFrames.startOver()
		selection.forget(fixture)
		context.delete(fixture)
	}
	
	func duplicate(_ fixture: Fixture, among fixtures: [Fixture], library: FixtureLibrary, context: ModelContext) {
		let width = max(1, library.type(fixture.typeID)?.channelCount ?? 1)
		let copy = Fixture(typeID: fixture.typeID, name: Fixture.unusedName(fixture.name, among: fixtures), address: DMXAddress(clamping: fixture.address + width), sortIndex: Self.nextSortIndex(fixtures, sortIndex: \.sortIndex))
		copy.symbolOverride = fixture.symbolOverride
		copy.invertsPan = fixture.invertsPan
		copy.invertsTilt = fixture.invertsTilt
		copy.groups = fixture.groups
		context.insert(copy)
	}
	
	func patch(_ mode: FixtureType, count: Int, at address: Int, named name: String, among fixtures: [Fixture], context: ModelContext) {
		let width = max(1, mode.channelCount)
		let base = name.trimmingCharacters(in: .whitespaces).isEmpty ? mode.model : name
		var next = address
		var index = Self.nextSortIndex(fixtures, sortIndex: \.sortIndex)
		
		for number in 0..<count {
			guard let start = DMXAddress(next) else { break }
			let title = count == 1 ? Fixture.unusedName(base, among: fixtures) : "\(base) \(number + 1)"
			let fixture = Fixture(typeID: mode.id, name: title, address: start, sortIndex: index)
			fixture.invertsPan = mode.invertsPan
			fixture.invertsTilt = mode.invertsTilt
			context.insert(fixture)
			Programmer(type: mode, start: start, console: self).applyDefaults()
			next += width
			index += 1
		}
	}
	
	static func nextSortIndex<Item>(_ items: [Item], sortIndex: KeyPath<Item, Double>) -> Double {
		(items.map { $0[keyPath: sortIndex] }.max() ?? 0) + 1
	}
	
	@available(iOS 27.0, *)
	func move<Item: PersistentModel>(_ difference: ReorderDifference<PersistentIdentifier, ReorderableSingleCollectionIdentifier>, among items: [Item], sortIndex: ReferenceWritableKeyPath<Item, Double>) {
		let ordered = items.filter { !difference.sources.contains($0.persistentModelID) }
		let lifted = items.filter { difference.sources.contains($0.persistentModelID) }
		
		switch difference.destination.position {
		case let .before(id): place(lifted, into: ordered, at: ordered.firstIndex { $0.persistentModelID == id } ?? ordered.endIndex, sortIndex: sortIndex)
		case .end: place(lifted, into: ordered, at: ordered.endIndex, sortIndex: sortIndex)
		}
	}
	
	func move<Item: PersistentModel>(_ offsets: IndexSet, to destination: Int, among items: [Item], sortIndex: ReferenceWritableKeyPath<Item, Double>) {
		let lifted = offsets.map { items[$0] }
		var ordered = items
		ordered.remove(atOffsets: offsets)
		
		var position = destination
		
		for offset in offsets where offset < destination {
			position -= 1
		}
		
		place(lifted, into: ordered, at: min(max(position, 0), ordered.count), sortIndex: sortIndex)
	}
	
	private func place<Item: PersistentModel>(_ lifted: [Item], into ordered: [Item], at position: Int, sortIndex: ReferenceWritableKeyPath<Item, Double>) {
		guard !lifted.isEmpty else { return }
		
		var low = 0.0
		var step = 1.0
		
		if position > 0 {
			low = ordered[position - 1][keyPath: sortIndex]
		} else if position < ordered.count {
			low = ordered[position][keyPath: sortIndex] - Double(lifted.count) - 1
		}
		
		if position > 0, position < ordered.count {
			step = (ordered[position][keyPath: sortIndex] - low) / Double(lifted.count + 1)
		}
		
		guard step > 0 else {
			var all = ordered
			all.insert(contentsOf: lifted, at: position)
			
			for (index, item) in all.enumerated() {
				item[keyPath: sortIndex] = Double(index)
			}
			return
		}
		
		for (offset, item) in lifted.enumerated() {
			item[keyPath: sortIndex] = low + step * Double(offset + 1)
		}
	}
	
	func levels(among fixtures: [Fixture], library: FixtureLibrary) -> [String: Data] {
		var levels: [String: Data] = [:]
		
		for fixture in fixtures {
			guard let profile = library.type(fixture.typeID) else { continue }
			var values = Data()
			
			for offset in 0..<profile.channelCount {
				guard let address = fixture.start.offset(by: offset) else { break }
				values.append(universe[address])
			}
			
			levels[fixture.identifier] = values
		}
		
		return levels
	}
	
	func recall(_ look: Look, among fixtures: [Fixture]) {
		for fixture in fixtures {
			guard let values = look.levels[fixture.identifier] else { continue }
			universe.set([UInt8](values), at: fixture.start)
		}
		
		outputFrames.startOver()
	}
	
	func applyPatch(_ fixtures: [Fixture], library: FixtureLibrary) {
		if !hasLoadedPatch, !library.types.isEmpty {
			hasLoadedPatch = true
			universe = Universe()
			active = []
			
			for fixture in fixtures {
				guard let type = library.type(fixture.typeID) else { continue }
				universe.set(type.defaults, at: fixture.start)
			}
			
			sourceFrames.startOver()
		}
		
		var covered: Set<Int> = []
		
		for fixture in fixtures {
			for address in fixture.range(library.type(fixture.typeID)) {
				covered.insert(address)
			}
		}
		
		for address in patched.subtracting(covered) {
			guard let slot = DMXAddress(address) else { continue }
			universe.set([0], at: slot)
			active.remove(address)
		}
		
		patched = covered
		
		let rebuilt = fixtures.flatMap { Programmer(fixture: $0, library: library, console: self)?.dimmers ?? [] }
		guard rebuilt != dimmers else { return }
		dimmers = rebuilt
		outputFrames.startOver()
	}
	
	var output: [UInt8] {
		let level = blackout ? 0 : master
		guard level < 1 else { return universe.values }
		
		var values = universe.values
		
		for dimmer in dimmers {
			let index = dimmer.address.value - 1
			if let fine = dimmer.fineAddress {
				let fineIndex = fine.value - 1
				let combined = Double(Int(values[index]) * 256 + Int(values[fineIndex]))
				let scaled = UInt16((combined * level).rounded())
				values[index] = UInt8(scaled >> 8)
				values[fineIndex] = UInt8(scaled & 0xFF)
			} else {
				values[index] = dimmer.scale(values[index], by: level)
			}
		}
		
		return values
	}
	
	private func tick() async {
		guard link.isConnected, isSynced else { return }
		
		if let frame = sourceFrames.next(universe.values) {
			await connection.send(Wire.sourceOpcode, start: frame.start, values: frame.values)
		}
		
		if let frame = outputFrames.next(output) {
			await connection.send(Wire.outputOpcode, start: frame.start, values: frame.values)
		}
	}
	
}
