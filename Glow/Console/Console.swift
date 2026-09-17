import Observation
import SwiftData
import SwiftUI

typealias Reorder = ReorderDifference<PersistentIdentifier, ReorderableSingleCollectionIdentifier>

@Observable @MainActor
final class Console {
	private(set) var universe = Universe()
	private(set) var link: LinkState = .offline
	private(set) var node: Wire.NodeInfo?
	private(set) var latency: TimeInterval?
	
	var selection: Set<PersistentIdentifier> = []
	var isProgrammerOpen = false
	
	var master: Double = 1 {
		didSet {
			needsFullOutput = true
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
			needsFullOutput = true
			guard !isAdopting else { return }
			let value = blackout
			
			Task {
				await connection.send(.blackout(value))
			}
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
	private var lastSource: [UInt8] = []
	private var lastOutput: [UInt8] = []
	private var needsFullSource = true
	private var needsFullOutput = true
	private var isSynced = false
	private var isAdopting = false
	private var savedLook: [UInt8] = []
	private var lastSave = Date.distantPast
	
	private static let endpointKey = "node.endpoint"
	
	private static var lookFile: URL {
		URL.applicationSupportDirectory.appending(path: "look.dmx")
	}
	
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
					if state == .connected {
						isSynced = false
						needsFullSource = true
						needsFullOutput = true
					}
				case let .status(info):
					node = info
					if !info.hasSource { isSynced = true }
				case let .latency(value):
					latency = value
				case let .frame(start, values):
					universe.set(values, at: start)
					lastSource = universe.values
					needsFullOutput = true
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
		needsFullSource = true
		needsFullOutput = true
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
	}
	
	func set(_ values: [UInt8], at address: DMXAddress) {
		universe.set(values, at: address)
	}
	
	
	var hasSelection: Bool { !selection.isEmpty }
	
	var isInspectingSelection: Bool {
		get { hasSelection }
		set { if !newValue { clearSelection() } }
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
		
		isProgrammerOpen = isProgrammerOpen && hasSelection
	}
	
	func toggle(_ group: FixtureGroup) {
		let members = Set(group.members.map(\.persistentModelID))
		if members.isSubset(of: selection) {
			selection.subtract(members)
		} else {
			selection.formUnion(members)
		}
		
		isProgrammerOpen = isProgrammerOpen && hasSelection
	}
	
	func clearSelection() {
		selection.removeAll()
		isProgrammerOpen = false
	}
	
	func releaseValues(among fixtures: [Fixture], library: FixtureLibrary) {
		programmer(among: fixtures, library: library).applyDefaults()
		clearSelection()
	}
	
	func programmer(among fixtures: [Fixture], library: FixtureLibrary) -> Programmer {
		Programmer(fixtures: fixtures.filter(isSelected), library: library, console: self)
	}
	
	func remove(_ fixture: Fixture, context: ModelContext, library: FixtureLibrary) {
		let width = max(1, library.profile(fixture.profileID)?.channelCount ?? 1)
		universe.set([UInt8](repeating: 0, count: width), at: fixture.start)
		needsFullOutput = true
		selection.remove(fixture.persistentModelID)
		isProgrammerOpen = isProgrammerOpen && hasSelection
		context.delete(fixture)
	}
	
	func duplicate(_ fixture: Fixture, among fixtures: [Fixture], library: FixtureLibrary, context: ModelContext) {
		let width = max(1, library.profile(fixture.profileID)?.channelCount ?? 1)
		let copy = Fixture(profileID: fixture.profileID, name: Fixture.unusedName(fixture.name, among: fixtures), address: DMXAddress(clamping: fixture.address + width), sortIndex: Self.nextSortIndex(fixtures, sortIndex: \.sortIndex))
		copy.symbolOverride = fixture.symbolOverride
		copy.tintName = fixture.tintName
		copy.group = fixture.group
		context.insert(copy)
	}
	
	func patch(_ profile: FixtureProfile, count: Int, at address: Int, named name: String, among fixtures: [Fixture], context: ModelContext) {
		let width = max(1, profile.channelCount)
		let base = name.trimmingCharacters(in: .whitespaces).isEmpty ? profile.model : name
		var next = address
		var index = Self.nextSortIndex(fixtures, sortIndex: \.sortIndex)
		
		for number in 0..<count {
			guard let start = DMXAddress(next) else { break }
			let title = count == 1 ? Fixture.unusedName(base, among: fixtures) : "\(base) \(number + 1)"
			context.insert(Fixture(profileID: profile.id, name: title, address: start, sortIndex: index))
			Programmer(profile: profile, start: start, console: self).applyDefaults()
			next += width
			index += 1
		}
	}
	
	static func nextSortIndex<Item>(_ items: [Item], sortIndex: KeyPath<Item, Int>) -> Int {
		(items.map { $0[keyPath: sortIndex] }.max() ?? 0) + 1
	}
	
	func move<Item: PersistentModel>(_ difference: Reorder, among items: [Item], sortIndex: ReferenceWritableKeyPath<Item, Int>) {
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
		
		needsFullOutput = true
	}
	
	func prune(_ fixtures: [Fixture], library: FixtureLibrary, context: ModelContext) {
		guard !library.profiles.isEmpty else { return }
		
		for fixture in fixtures where library.profile(fixture.profileID) == nil {
			remove(fixture, context: context, library: library)
		}
	}
	
	func applyPatch(_ fixtures: [Fixture], library: FixtureLibrary) {
		let rebuilt = fixtures.flatMap { Programmer(fixture: $0, library: library, console: self)?.dimmers ?? [] }
		guard rebuilt != dimmers else { return }
		dimmers = rebuilt
		needsFullOutput = true
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
		guard link.isConnected, isSynced else { return }
		await sendSource()
		await sendOutput()
	}
	
	private func sendSource() async {
		let frame = universe.values
		defer { lastSource = frame }
		
		guard !needsFullSource, lastSource.count == frame.count else {
			needsFullSource = false
			await connection.send(Wire.sourceOpcode, start: DMXAddress(1)!, values: frame)
			return
		}
		
		guard let span = Self.changed(lastSource, frame), let start = DMXAddress(span.lowerBound + 1) else { return }
		await connection.send(Wire.sourceOpcode, start: start, values: Array(frame[span]))
	}
	
	private func sendOutput() async {
		let frame = output()
		defer { lastOutput = frame }
		
		guard !needsFullOutput, lastOutput.count == frame.count else {
			needsFullOutput = false
			await connection.send(Wire.outputOpcode, start: DMXAddress(1)!, values: frame)
			return
		}
		
		guard let span = Self.changed(lastOutput, frame), let start = DMXAddress(span.lowerBound + 1) else { return }
		await connection.send(Wire.outputOpcode, start: start, values: Array(frame[span]))
	}
	
	private static func changed(_ old: [UInt8], _ new: [UInt8]) -> ClosedRange<Int>? {
		var first: Int?
		var last: Int?
		
		for index in new.indices where old[index] != new[index] {
			if first == nil { first = index }
			last = index
		}
		
		guard let first, let last else { return nil }
		return first...last
	}
	
	private func restoreLook() {
		try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
		guard let data = try? Data(contentsOf: Self.lookFile), data.count == Universe.channelCount else { return }
		universe.set([UInt8](data), at: DMXAddress(1)!)
		savedLook = [UInt8](data)
		needsFullSource = true
		needsFullOutput = true
	}
	
	private func saveLook() {
		guard universe.values != savedLook, Date().timeIntervalSince(lastSave) > 2 else { return }
		savedLook = universe.values
		lastSave = Date()
		try? Data(universe.values).write(to: Self.lookFile)
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
