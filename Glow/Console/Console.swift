import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class Console {
	private(set) var universe = Universe()
	private(set) var link: LinkState = .offline
	private(set) var node: Wire.NodeInfo?
	private(set) var latency: TimeInterval?
	
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
	
	private let connection = NodeLink()
	private var dimmers: [Dimmer] = []
	private var loop: Task<Void, Never>?
	private var events: Task<Void, Never>?
	private var sourceFrames = FrameStream()
	private var outputFrames = FrameStream()
	private var isSynced = false
	private var isAdopting = false
	private var savedLook: [UInt8] = []
	private var lastSave = Date.distantPast
	
	private static let endpointKey = "node.endpoint"
	
	private static var lookFile: URL {
		URL.applicationSupportDirectory.appending(path: "look.dmx")
	}
	
	init() {
		if let data = UserDefaults.standard.data(forKey: Self.endpointKey), let stored = try? JSONDecoder().decode(NodeEndpoint.self, from: data) {
			endpoint = stored
		} else {
			endpoint = .fallback
		}
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
		selection.clear()
		sourceFrames.startOver()
		outputFrames.startOver()
	}
	
	func releaseValues(among fixtures: [Fixture], library: FixtureLibrary) {
		programmer(among: fixtures, library: library).applyDefaults()
		selection.clear()
	}
	
	func programmer(among fixtures: [Fixture], library: FixtureLibrary) -> Programmer {
		Programmer(fixtures: fixtures.filter(selection.contains), library: library, console: self)
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
		copy.group = fixture.group
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
	
	static func nextSortIndex<Item>(_ items: [Item], sortIndex: KeyPath<Item, Int>) -> Int {
		(items.map { $0[keyPath: sortIndex] }.max() ?? 0) + 1
	}
	
	@available(iOS 27.0, *)
	func move<Item: PersistentModel>(_ difference: ReorderDifference<PersistentIdentifier, ReorderableSingleCollectionIdentifier>, among items: [Item], sortIndex: ReferenceWritableKeyPath<Item, Int>) {
		var ordered = items.filter { !difference.sources.contains($0.persistentModelID) }
		let lifted = items.filter { difference.sources.contains($0.persistentModelID) }
		
		switch difference.destination.position {
		case let .before(id): ordered.insert(contentsOf: lifted, at: ordered.firstIndex { $0.persistentModelID == id } ?? ordered.endIndex)
		case .end: ordered.append(contentsOf: lifted)
		}
		
		for (index, item) in ordered.enumerated() {
			item[keyPath: sortIndex] = index
		}
	}
	
	func move<Item: PersistentModel>(_ offsets: IndexSet, to destination: Int, among items: [Item], sortIndex: ReferenceWritableKeyPath<Item, Int>) {
		var ordered = items
		ordered.move(fromOffsets: offsets, toOffset: destination)
		
		for (index, item) in ordered.enumerated() {
			item[keyPath: sortIndex] = index
		}
	}
	
	func levels(among fixtures: [Fixture], library: FixtureLibrary) -> [String: [UInt8]] {
		var levels: [String: [UInt8]] = [:]
		
		for fixture in fixtures {
			guard let profile = library.type(fixture.typeID) else { continue }
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
		
		outputFrames.startOver()
	}
	
	func applyPatch(_ fixtures: [Fixture], library: FixtureLibrary) {
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
		saveLook()
		guard link.isConnected, isSynced else { return }
		
		if let frame = sourceFrames.next(universe.values) {
			await connection.send(Wire.sourceOpcode, start: frame.start, values: frame.values)
		}
		
		if let frame = outputFrames.next(output) {
			await connection.send(Wire.outputOpcode, start: frame.start, values: frame.values)
		}
	}
	
	private func restoreLook() {
		try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
		guard let data = try? Data(contentsOf: Self.lookFile), data.count == Universe.channelCount else { return }
		universe.set([UInt8](data), at: DMXAddress(1)!)
		savedLook = [UInt8](data)
		sourceFrames.startOver()
		outputFrames.startOver()
	}
	
	private func saveLook() {
		guard universe.values != savedLook, Date().timeIntervalSince(lastSave) > 2 else { return }
		savedLook = universe.values
		lastSave = Date()
		try? Data(universe.values).write(to: Self.lookFile)
	}
}
