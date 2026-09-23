import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class Console {
	private(set) var universe = Universe() {
		didSet { ring() }
	}
	
	private(set) var link: LinkState = .offline
	private(set) var node: Wire.NodeInfo?
	private(set) var latency: TimeInterval?
	private(set) var activeScene: String?
	
	let selection = Selection()
	let notices: AsyncStream<Wire.Notice>
	
	var master: Double = 1 {
		didSet { ring() }
	}
	
	var blackout = false {
		didSet { ring() }
	}
	
	var endpoint: NodeEndpoint {
		didSet {
			if let data = try? JSONEncoder().encode(endpoint) {
				UserDefaults.standard.set(data, forKey: Self.endpointKey)
			}
			isConfigured = true
			connect()
		}
	}
	
	private(set) var isConfigured = false
	
	private(set) var active: Set<Int> = []
	private(set) var patched: Set<Int> = []
	private(set) var span = Universe.minimumSlots
	private(set) var resets = 0
	
	private let connection = NodeLink()
	private let bell: AsyncStream<Void>
	private let ringer: AsyncStream<Void>.Continuation
	private let noticer: AsyncStream<Wire.Notice>.Continuation
	private var dimmers: [Dimmer] = [] {
		didSet { ring() }
	}
	private var outbox: [URLSessionWebSocketTask.Message] = [] {
		didSet { ring() }
	}
	private var isSynced = false {
		didSet { ring() }
	}
	private var loop: Task<Void, Never>?
	private var events: Task<Void, Never>?
	private var sourceFrames = FrameStream()
	private var outputFrames = FrameStream()
	private var announcedMaster: Double?
	private var announcedBlackout: Bool?
	private var hasAdoptedSource = false
	private var hasLoadedPatch = false
	
	private static let endpointKey = "node.endpoint"
	private static let addressKey = "node.address"
	
	init() {
		(bell, ringer) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
		(notices, noticer) = AsyncStream<Wire.Notice>.makeStream()
		
		if let data = UserDefaults.standard.data(forKey: Self.endpointKey), let stored = try? JSONDecoder().decode(NodeEndpoint.self, from: data) {
			endpoint = stored
			isConfigured = true
		} else {
			endpoint = .fallback
		}
	}
	
	func start() {
		guard events == nil else { return }
		
		events = Task { [weak self] in
			guard let stream = self?.connection.events else { return }
			
			for await event in stream {
				self?.handle(event)
			}
		}
		
		loop = Task { [weak self] in
			guard let bell = self?.bell else { return }
			
			for await _ in bell {
				await self?.tick()
				try? await Task.sleep(for: .milliseconds(10))
			}
		}
		
		connect()
	}
	
	func connect() {
		isSynced = false
		let target = endpoint
		let known = UserDefaults.standard.string(forKey: Self.addressKey)
		
		Task {
			await connection.prefer(known)
			await connection.connect(to: target)
		}
	}
	
	private func handle(_ event: NodeLink.Event) {
		switch event {
		case let .state(state):
			link = state
			isSynced = false
			outbox = []
			guard state == .connected else { return }
			hasAdoptedSource = false
			announcedMaster = nil
			announcedBlackout = nil
			sourceFrames.cover(span)
			outputFrames.cover(span)
			sourceFrames.startOver()
			outputFrames.startOver()
			outbox = [Wire.Command.span(span).message]
		case let .status(info):
			node = info
			activeScene = info.scene.isEmpty ? nil : info.scene
			
			if !info.address.isEmpty, info.address != UserDefaults.standard.string(forKey: Self.addressKey) {
				UserDefaults.standard.set(info.address, forKey: Self.addressKey)
			}
			
			if info.hasSource {
				master = info.master
				blackout = info.blackout
				announcedMaster = info.master
				announcedBlackout = info.blackout
			} else {
				isSynced = true
			}
		case let .latency(value):
			latency = value
		case .pong:
			break
		case let .frame(start, values):
			universe.set(values, at: start)
			sourceFrames.adopt(universe.values, start: start, count: values.count)
			outputFrames.adopt(output, start: start, count: values.count)
			hasAdoptedSource = true
			isSynced = true
		case let .master(level):
			master = level
			announcedMaster = level
		case let .blackout(on):
			blackout = on
			announcedBlackout = on
		case let .scene(identifier):
			activeScene = identifier
		case let .notice(notice):
			noticer.yield(notice)
		}
	}
	
	private func cover(_ reach: Int) {
		guard reach != span else { return }
		span = reach
		sourceFrames.cover(reach)
		outputFrames.cover(reach)
		outbox.append(Wire.Command.span(reach).message)
	}
	
	private func ring() {
		ringer.yield()
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
	
	var reachable: NodeEndpoint {
		guard let address = node?.address, !address.isEmpty else { return endpoint }
		return NodeEndpoint(host: address, port: endpoint.port, name: endpoint.name, nodeID: endpoint.nodeID)
	}
	
	func send(document frame: Data) {
		outbox.append(.data(frame))
	}
	
	func closeShow() {
		universe = Universe()
		active = []
		dimmers = []
		patched = []
		activeScene = nil
		cover(Universe.minimumSlots)
		hasAdoptedSource = false
		hasLoadedPatch = false
		selection.clear()
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
		change(fixture)
		guard let type = library.type(fixture.typeID) else { return }
		universe.set(type.defaults, at: fixture.start)
		release(fixture.range(type))
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
			guard let type = library.type(fixture.typeID) else { continue }
			let first = fixture.start.value - 1
			levels[fixture.identifier] = Data(universe.values[first..<min(first + type.channelCount, Universe.channelCount)])
		}
		
		return levels
	}
	
	func recall(_ look: Look, among fixtures: [Fixture]) {
		let levels = look.levels
		let identifier = look.identifier
		
		for fixture in fixtures {
			guard let values = levels[fixture.identifier] else { continue }
			universe.set([UInt8](values), at: fixture.start)
		}
		
		activeScene = identifier
		outbox.append(Wire.Command.scene(identifier).message)
	}
	
	func applyPatch(_ fixtures: [Fixture], library: FixtureLibrary) {
		if !hasLoadedPatch, !library.types.isEmpty {
			hasLoadedPatch = true
			
			if !hasAdoptedSource {
				universe = Universe()
				active = []
				
				for fixture in fixtures {
					guard let type = library.type(fixture.typeID) else { continue }
					universe.set(type.defaults, at: fixture.start)
				}
			}
		}
		
		var covered: Set<Int> = []
		
		for fixture in fixtures {
			covered.formUnion(fixture.range(library.type(fixture.typeID)))
		}
		
		for address in patched.subtracting(covered) {
			guard let slot = DMXAddress(address) else { continue }
			universe.set([0], at: slot)
			active.remove(address)
		}
		
		patched = covered
		selection.keep(Set(fixtures.map(\.identifier)))
		
		cover(max(covered.max() ?? 0, Universe.minimumSlots))
		
		let rebuilt = fixtures.flatMap { Programmer(fixture: $0, library: library, console: self)?.dimmers ?? [] }
		guard rebuilt != dimmers else { return }
		dimmers = rebuilt
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
		var messages = outbox
		outbox = []
		
		if master != announcedMaster {
			announcedMaster = master
			messages.append(Wire.Command.master(master).message)
		}
		
		if blackout != announcedBlackout {
			announcedBlackout = blackout
			messages.append(Wire.Command.blackout(blackout).message)
		}
		
		if let frame = sourceFrames.next(universe.values) {
			messages.append(.data(Wire.frame(Wire.sourceOpcode, start: frame.start, values: frame.values)))
		}
		
		if let frame = outputFrames.next(output) {
			messages.append(.data(Wire.frame(Wire.outputOpcode, start: frame.start, values: frame.values)))
		}
		
		for message in messages {
			await connection.send(message)
		}
	}
}
