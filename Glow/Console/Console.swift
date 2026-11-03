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
	private(set) var usage: Wire.Usage?
	private(set) var playback = Playback()
	private(set) var lock: Wire.Lock?
	private(set) var lockedUntil: Date?
	private(set) var isUnlocking = false
	var passwordOutcome: PasswordOutcome?
	
	let selection = Selection()
	let notices: AsyncStream<Wire.Notice>
	
	var master: Double = 1 {
		didSet { level() }
	}
	
	var blackout = false {
		didSet { level() }
	}
	
	var isMuted = false {
		didSet { ring() }
	}
	
	var lists: [String: CueList] = [:] {
		didSet { resume() }
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
	
	private(set) var active: [Int: UInt8] = [:]
	private var defaulted: Set<Int> = []
	private(set) var patched: Set<Int> = []
	private(set) var span = Universe.minimumSlots
	private(set) var resets = 0
	private(set) var commands = 0
	
	private let connection = NodeLink()
	private let bell: AsyncStream<Void>
	private let ringer: AsyncStream<Void>.Continuation
	private let noticer: AsyncStream<Wire.Notice>.Continuation
	private let stage = stage_new()!
	private let born = ContinuousClock.now
	private var outbox: [URLSessionWebSocketTask.Message] = []
	private var draining: Task<Void, Never>?
	private var isSynced = false {
		didSet { ring() }
	}
	private var events: Task<Void, Never>?
	private var frames = FrameStream()
	private var scratch = [UInt8](repeating: 0, count: Int(STAGE_FRAME_MAX))
	private var map = Data([Wire.mapOpcode])
	private var announcedMaster: Double?
	private var announcedBlackout: Bool?
	private var hasAdoptedSource = false
	private var hasLoadedPatch = false
	private var offered: Data?
	private var proposed: Data?
	private var pause: Task<Void, Never>?
	private var running: Task<Void, Never>?
	private var sent = 0
	private var acked = 0
	private(set) var flashing: Set<String> = []
	private var continued: [String: String] = [:]
	
	private static let endpointKey = "node.endpoint"
	private static let addressKey = "node.address"
	private static let ownClient = 0
	
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
	
	isolated deinit {
		stage_free(stage)
	}
	
	func start() {
		guard events == nil else { return }
		
		events = Task { [weak self] in
			guard let stream = self?.connection.events else { return }
			
			for await event in stream {
				self?.handle(event)
			}
		}
		
		Task { [weak self] in
			guard let bell = self?.bell else { return }
			
			for await _ in bell {
				self?.tick()
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
			await connection.connect(to: target, preferring: known)
		}
	}
	
	private func handle(_ event: NodeLink.Event) {
		switch event {
		case let .state(state):
			link = state
			isSynced = false
			outbox = []
			guard state == .connected else {
				usage = nil
				return
			}
			hasAdoptedSource = false
			announcedMaster = nil
			announcedBlackout = nil
			sent = 0
			acked = 0
			continued = [:]
			stage_clear(stage)
			frames.cover(span)
			frames.startOver()
			outbox = [Wire.Command.span(span).message] + (map.count > 1 ? [.data(map)] : [])
		case let .status(info):
			node = info
			
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
			
			if let offered, let lock {
				Passkey.store(offered, id: lock.id)
			}
			
			offered = nil
			lock = nil
			lockedUntil = nil
			isUnlocking = false
			pause?.cancel()
		case .locked(var challenge):
			if challenge.isWrong, offered == Passkey.stored(id: challenge.id) {
				Passkey.forget(id: challenge.id)
				challenge.isWrong = false
			}
			
			lock = challenge
			offered = nil
			isUnlocking = false
			lockedUntil = nil
			pause?.cancel()
			
			guard challenge.wait == 0 else {
				lockedUntil = Date().addingTimeInterval(TimeInterval(challenge.wait))
				pause = Task { [weak self] in
					try? await Task.sleep(for: .seconds(challenge.wait))
					guard !Task.isCancelled, let self else { return }
					lockedUntil = nil
					guard let key = Passkey.stored(id: challenge.id) else { return }
					offer(key)
				}
				return
			}
			
			guard !challenge.isWrong, let key = Passkey.stored(id: challenge.id) else { return }
			offer(key)
		case let .password(isSet):
			node?.hasPassword = isSet
			
			let id = node?.id ?? ""
			
			if let proposed {
				Passkey.store(proposed, id: id)
			} else {
				Passkey.forget(id: id)
			}
			
			proposed = nil
			if passwordOutcome == .saving { passwordOutcome = .saved }
		case let .passwordRefused(outcome):
			proposed = nil
			passwordOutcome = outcome
		case let .latency(value):
			latency = value
		case let .usage(value):
			usage = value
		case .pong:
			break
		case let .frame(ack, runs):
			frames.adopt(runs, ack: ack, into: &universe)
			guard runs.count == 1, runs[0].start.value == 1, runs[0].values.count == Universe.channelCount else { return }
			hasAdoptedSource = true
			isSynced = true
		case let .master(level):
			master = level
			announcedMaster = level
		case let .blackout(on):
			blackout = on
			announcedBlackout = on
		case let .playback(state):
			take(state)
		case let .notice(notice):
			noticer.yield(notice)
		}
	}
	
	func unlock(password: String) {
		guard let lock, !isUnlocking, lockedUntil == nil else { return }
		isUnlocking = true
		
		Task {
			offer(await Passkey.derive(password, id: lock.id))
		}
	}
	
	func protect(current: String, new: String) {
		guard let node else { return }
		passwordOutcome = .saving
		
		Task {
			var old: Data?
			var fresh: Data?
			
			if node.hasPassword {
				old = await Passkey.derive(current, id: node.id)
			}
			
			if !new.isEmpty {
				fresh = await Passkey.derive(new, id: node.id)
			}
			
			proposed = fresh
			send(.password(old: old, new: fresh, nonce: node.nonce))
		}
	}
	
	private func offer(_ key: Data) {
		guard let lock else { return }
		isUnlocking = true
		offered = key
		let message = Wire.Command.unlock(key: key, nonce: lock.nonce).message
		
		Task {
			await connection.send(message)
		}
	}
	
	private func cover(_ reach: Int) {
		guard reach != span else { return }
		span = reach
		frames.cover(reach)
		post(Wire.Command.span(reach).message)
	}
	
	private func ring() {
		ringer.yield()
	}
	
	private func level() {
		stage_levels(stage, Float(master), blackout)
		ring()
	}
	
	private var now: UInt32 {
		UInt32(truncatingIfNeeded: Int((ContinuousClock.now - born) / .milliseconds(1)))
	}
	
	func value(at address: DMXAddress) -> UInt8 {
		universe[address]
	}
	
	func set(_ value: UInt8, at address: DMXAddress) {
		if active[address.value] == nil { active[address.value] = universe[address] }
		universe[address] = value
	}
	
	func set(_ values: [UInt8], at address: DMXAddress) {
		universe.set(values, at: address)
	}
	
	func restore(_ defaults: [UInt8], at start: DMXAddress) {
		set(defaults, at: start)
		
		for slot in start.value..<(start.value + defaults.count) {
			active[slot] = nil
			defaulted.insert(slot)
		}
	}
	
	func isActive(_ address: DMXAddress) -> Bool {
		active[address.value] != nil
	}
	
	func isChanged(_ address: DMXAddress) -> Bool {
		defaulted.contains(address.value) || active[address.value].map { $0 != universe[address] } ?? false
	}
	
	func release(_ span: ClosedRange<Int>, only offset: Int? = nil) {
		guard let offset else {
			active = active.filter { !span.contains($0.key) }
			defaulted.subtract(span)
			return
		}
		
		active[span.lowerBound + offset - 1] = nil
		defaulted.remove(span.lowerBound + offset - 1)
	}
	
	var reachable: NodeEndpoint {
		var target = endpoint
		target.session = node?.session
		guard let address = node?.address, !address.isEmpty else { return target }
		target.host = address
		return target
	}
	
	func send(document frame: Data) {
		post(.data(frame))
	}
	
	func send(_ command: Wire.Command) {
		post(command.message)
	}
	
	func closeShow(keepingLook: Bool = false) {
		playback = Playback()
		flashing = []
		continued = [:]
		stage_clear(stage)
		
		if !keepingLook || !hasAdoptedSource {
			universe = Universe()
			hasAdoptedSource = false
		}
		
		active = [:]
		defaulted = []
		map = Data([Wire.mapOpcode])
		patched = []
		cover(Universe.minimumSlots)
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
		let copy = Fixture(typeID: fixture.typeID, name: Identifier.unusedName(fixture.name, among: fixtures.map(\.name)), address: DMXAddress(clamping: fixture.address + width), sortIndex: Self.nextSortIndex(fixtures, sortIndex: \.sortIndex))
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
			let title = count == 1 ? Identifier.unusedName(base, among: fixtures.map(\.name)) : "\(base) \(number + 1)"
			let fixture = Fixture(typeID: mode.id, name: title, address: start, sortIndex: index)
			fixture.invertsPan = mode.invertsPan
			fixture.invertsTilt = mode.invertsTilt
			context.insert(fixture)
			universe.set(mode.defaults, at: start)
			release(fixture.range(mode))
			next += width
			index += 1
		}
	}
	
	static func nextSortIndex<Item>(_ items: [Item], sortIndex: KeyPath<Item, Double>) -> Double {
		(items.map { $0[keyPath: sortIndex] }.max() ?? 0) + 1
	}
	
	static func sortIndex(between low: Double, and high: Double) -> Double? {
		let next = low + max(((high - low) * 128).rounded(.down), 1) / 256
		return next < high ? next : nil
	}
	
	@available(iOS 27.0, *)
	func move<Item: PersistentModel>(_ difference: ReorderDifference<PersistentIdentifier, ReorderableSingleCollectionIdentifier>, among items: [Item], sortIndex: ReferenceWritableKeyPath<Item, Double>) {
		var destination = items.endIndex
		
		if case let .before(id) = difference.destination.position {
			destination = items.firstIndex { $0.persistentModelID == id } ?? items.endIndex
		}
		
		move(IndexSet(items.indices.filter { difference.sources.contains(items[$0].persistentModelID) }), to: destination, among: items, sortIndex: sortIndex)
	}
	
	func move<Item: PersistentModel>(_ offsets: IndexSet, to destination: Int, among items: [Item], sortIndex: ReferenceWritableKeyPath<Item, Double>) {
		let lifted = offsets.map { items[$0] }
		guard !lifted.isEmpty else { return }
		var ordered = items
		ordered.remove(atOffsets: offsets)
		let position = min(max(destination - offsets.count { $0 < destination }, 0), ordered.count)
		
		var low = 0.0
		var step = 1.0
		
		if position > 0 {
			low = ordered[position - 1][keyPath: sortIndex]
		} else if position < ordered.count, ordered[position][keyPath: sortIndex] <= 0 {
			low = ordered[position][keyPath: sortIndex] - Double(lifted.count) - 1
		}
		
		if position < ordered.count, position > 0 || ordered[position][keyPath: sortIndex] > 0 {
			step = ((ordered[position][keyPath: sortIndex] - low) / Double(lifted.count + 1) * 256).rounded(.down) / 256
		}
		
		guard step > 0 else {
			ordered.insert(contentsOf: lifted, at: position)
			
			for (index, item) in ordered.enumerated() {
				item[keyPath: sortIndex] = Double(index)
			}
			return
		}
		
		for (offset, item) in lifted.enumerated() {
			item[keyPath: sortIndex] = low + step * Double(offset + 1)
		}
	}
	
	func run(_ action: SceneAction, on list: CueList) {
		switch action {
		case .toggle: toggle(list)
		case .next:
			if upcoming(list) == nil {
				stop(list)
			} else {
				go(list)
			}
		case .back: back(list)
		case .restart: play(list, at: 0)
		case .stop: stop(list)
		case .flash, .open: break
		}
	}
	
	func toggle(_ list: CueList) {
		guard list.index(of: playback.cue(of: list.scene)) == nil else {
			stop(list)
			return
		}
		
		go(list)
	}
	
	func shownScene(among scenes: [String]) -> String? {
		[selection.scene, playback.playing.last?.scene].compactMap { $0 }.first(where: scenes.contains) ?? scenes.first
	}
	
	func stopAll() {
		for entry in playback.playing.reversed() {
			stop(entry.scene, fade: lists[entry.scene]?.fade(of: entry.cue) ?? 0)
		}
	}
	
	func flash(_ list: CueList, isHeld: Bool) {
		guard isHeld else {
			guard flashing.remove(list.scene) != nil else { return }
			stop(list, snapping: true)
			return
		}
		
		guard playback.cue(of: list.scene) == nil, !list.cues.isEmpty else { return }
		play(list, at: 0, snapping: true)
		flashing.insert(list.scene)
	}
	
	func go(_ list: CueList) {
		guard let index = upcoming(list) else { return }
		play(list, at: index)
	}
	
	func upcoming(_ list: CueList) -> Int? {
		list.index(of: selection.armed[list.scene]) ?? list.next(after: list.index(of: playback.cue(of: list.scene)))
	}
	
	func back(_ list: CueList) {
		guard let current = list.index(of: playback.cue(of: list.scene)), let index = list.previous(before: current) else { return }
		play(list, at: index)
	}
	
	func play(_ list: CueList, at index: Int, snapping: Bool = false) {
		guard list.cues.indices.contains(index), command(.play, scene: list.scene, body: list.program(from: index, snapping: snapping)) else { return }
		let cue = list.cues[index]
		let start = Date.now.addingTimeInterval(cue.delay)
		flashing.remove(list.scene)
		selection.armed[list.scene] = nil
		playback.play(cue.identifier, of: list.scene, fade: snapping ? Fade(start: .now, end: .now, follows: false) : Fade(start: start, end: start.addingTimeInterval(cue.fade)))
	}
	
	func land(_ list: CueList, at index: Int) {
		guard list.cues.indices.contains(index), command(.land, scene: list.scene, body: list.program(from: index, snapping: true)) else { return }
		flashing.remove(list.scene)
		playback.play(list.cues[index].identifier, of: list.scene, fade: Fade(start: .now, end: .now, follows: false))
	}
	
	func stop(_ list: CueList, snapping: Bool = false) {
		stop(list.scene, fade: snapping ? 0 : list.fade(of: playback.cue(of: list.scene)))
	}
	
	func delete(_ chosen: [Cue], from list: CueList, context: ModelContext) {
		let gone = Set(chosen.map(\.identifier))
		release(gone, from: list)
		
		for cue in chosen {
			context.delete(cue)
		}
	}
	
	func duplicate(_ chosen: [Cue], among held: [Cue], context: ModelContext) {
		let picked = Set(chosen.map(\.identifier))
		guard let last = held.lastIndex(where: { picked.contains($0.identifier) }) else { return }
		var ordered = held
		var copies: [Cue] = []
		
		for cue in held where picked.contains(cue.identifier) {
			var entry = cue.entry
			entry.identifier = Identifier.fresh()
			let copy = Cue(lookID: cue.lookID, sortIndex: cue.sortIndex, fade: cue.fade, levels: Levels())
			copy.take(entry)
			context.insert(copy)
			copies.append(copy)
		}
		
		ordered.insert(contentsOf: copies, at: last + 1)
		
		for (index, cue) in ordered.enumerated() where cue.sortIndex != Double(index + 1) {
			cue.sortIndex = Double(index + 1)
		}
	}
	
	func move(_ chosen: [Cue], from list: CueList, to look: Look, among cues: [Cue]) {
		let picked = Set(chosen.map(\.identifier))
		release(picked, from: list)
		let start = (look.cues(among: cues).last?.sortIndex ?? 0).rounded(.down) + 1
		
		for (offset, cue) in chosen.enumerated() {
			cue.lookID = look.identifier
			cue.sortIndex = start + Double(offset)
		}
	}
	
	func copy(_ chosen: [Cue], to look: Look, among cues: [Cue], context: ModelContext) {
		let start = (look.cues(among: cues).last?.sortIndex ?? 0).rounded(.down) + 1
		
		for (offset, cue) in chosen.enumerated() {
			var entry = cue.entry
			entry.identifier = Identifier.fresh()
			entry.scene = look.identifier
			entry.sortIndex = start + Double(offset)
			let copy = Cue(lookID: look.identifier, sortIndex: entry.sortIndex, fade: entry.fade, levels: Levels())
			copy.take(entry)
			context.insert(copy)
		}
	}
	
	func retime(_ chosen: [Cue], from start: CueDraft, to end: CueDraft) {
		for cue in chosen {
			if end.fade != start.fade { cue.fade = end.fade }
			if end.delay != start.delay { cue.delay = end.delay }
			if end.follow != start.follow { cue.follow = end.follow }
		}
	}
	
	private func release(_ gone: Set<String>, from list: CueList) {
		if let marked = selection.marked, gone.contains(marked), let index = list.index(of: marked) {
			let before = list.cues[..<index].last { !gone.contains($0.identifier) }
			let after = list.cues[index...].first { !gone.contains($0.identifier) }
			selection.marked = (before ?? after)?.identifier
		}
		
		if let armed = selection.armed[list.scene], gone.contains(armed) {
			selection.armed[list.scene] = nil
		}
		
		guard let live = playback.cue(of: list.scene), gone.contains(live), let index = list.index(of: live) else { return }
		let trimmed = gone.reduce(list) { $0.removing($1) }
		
		guard let first = trimmed.cues.first else {
			stop(list)
			return
		}
		
		let landing = list.cues[..<index].last { !gone.contains($0.identifier) } ?? first
		play(trimmed, at: trimmed.index(of: landing.identifier) ?? 0, snapping: true)
	}
	
	func remove(_ look: Look, with cues: [Cue], context: ModelContext) {
		stop(look.identifier, fade: lists[look.identifier]?.fade(of: playback.cue(of: look.identifier)) ?? 0)
		look.remove(with: cues, context: context)
	}
	
	func isMoving(_ scene: String) -> Bool {
		guard let fade = playback.fades[scene] else { return false }
		guard fade.end <= .now else { return true }
		guard fade.follows, let list = lists[scene], let index = list.index(of: playback.cue(of: scene)) else { return false }
		return list.cues[index].follow != nil && list.next(after: index) != nil
	}
	
	func marked(among held: [Cue]) -> Int? {
		held.firstIndex { $0.identifier == selection.marked } ?? held.indices.last
	}
	
	func keep(_ look: Look, among cues: [Cue], fixtures: [Fixture], library: FixtureLibrary) {
		guard selection.kept == nil else { return }
		let held = look.cues(among: cues)
		selection.kept = (look.entry, held.map(\.entry), playback.cue(of: look.identifier))
		selection.marked = playback.cue(of: look.identifier) ?? held.last?.identifier
		
		let levels = held.reduce(Levels()) { $0.merging($1.levels) }
		let aspects = Set(fixtures.flatMap { levels.features(of: $0.identifier, type: library.type($0.typeID)) })
		guard !aspects.isEmpty else { return }
		selection.seed.lights = Set(levels.lights.keys)
		selection.seed.aspects = aspects
		selection.draft = selection.seed
	}
	
	func hasChanged(_ look: Look, among cues: [Cue]) -> Bool {
		guard let kept = selection.kept else { return false }
		let held = look.cues(among: cues).map(\.entry)
		guard !selection.isNew || !held.isEmpty else { return false }
		return look.entry != kept.scene || held != kept.cues
	}
	
	func discard(_ look: Look, among cues: [Cue], fixtures: [Fixture], context: ModelContext) {
		let kept = selection.kept
		let isNew = selection.isNew
		selection.building = nil
		
		guard let kept else { return }
		
		guard !isNew else {
			remove(look, with: cues, context: context)
			return
		}
		
		let playing = look.cues(among: cues).first { $0.identifier == kept.playing }?.entry
		let moved = playback.cue(of: look.identifier) != kept.playing || playing != kept.cues.first { $0.identifier == kept.playing }
		look.take(kept.scene)
		
		for cue in look.cues(among: cues) where !kept.cues.contains(where: { $0.identifier == cue.identifier }) {
			context.delete(cue)
		}
		
		for entry in kept.cues {
			if let cue = cues.first(where: { $0.identifier == entry.identifier }) {
				cue.take(entry)
			} else {
				let cue = Cue(lookID: entry.scene, sortIndex: entry.sortIndex, fade: entry.fade, levels: Levels())
				cue.take(entry)
				context.insert(cue)
			}
		}
		
		try? context.save()
		guard moved else { return }
		let list = CueList(look, cues: (try? context.fetch(FetchDescriptor<Cue>())) ?? [], fixtures: fixtures)
		
		if let index = list.index(of: kept.playing) {
			play(list, at: index, snapping: true)
		} else {
			stop(look.identifier, fade: 0)
		}
	}
	
	private func stop(_ scene: String, fade: Double) {
		guard playback.cue(of: scene) != nil else { return }
		var writer = ByteWriter()
		writer.number(CueList.milliseconds(fade))
		guard command(.stop, scene: scene, body: writer.data) else { return }
		flashing.remove(scene)
		playback.stop(scene, fade: fade)
	}
	
	@discardableResult private func command(_ action: Wire.Action, scene: String, body: Data) -> Bool {
		guard isMuted || link.isConnected else { return false }
		sent = (sent + 1) & 0xFFFF
		if action == .play || action == .stop { commands += 1 }
		let message = Wire.command(action, seq: sent, scene: scene, body: body)
		flush()
		
		guard isMuted else {
			post(.data(message))
			return true
		}
		
		let bytes = [UInt8](message)
		stage_command(stage, bytes, bytes.count, UInt8(Self.ownClient), now)
		advance()
		announce()
		return true
	}
	
	private func take(_ state: [UInt8]) {
		guard state.count >= 4 else { return }
		if Int(state[1]) == (isMuted ? Self.ownClient : node?.client) { acked = Int(state[2]) | Int(state[3]) << 8 }
		guard acked == sent, let fresh = Playback(state, at: .now) else { return }
		if fresh.playing != playback.playing || fresh.fades.keys != playback.fades.keys { playback = fresh }
		continued = continued.filter { scene, cue in fresh.playing.contains { $0.scene == scene && $0.cue == cue && $0.wants } }
		resume()
	}
	
	private func resume() {
		guard acked == sent else { return }
		let own = isMuted ? Self.ownClient : node?.client
		
		for entry in playback.playing where entry.wants && [0xFF, own].contains(entry.caller) && continued[entry.scene] != entry.cue {
			guard let list = lists[entry.scene], let index = list.index(of: entry.cue) else { continue }
			continued[entry.scene] = entry.cue
			command(.more, scene: entry.scene, body: list.program(from: index))
		}
	}
	
	private func flush() {
		guard isMuted else {
			guard isSynced else { return }
			let runs = frames.next(universe.values)
			guard !runs.isEmpty else { return }
			outbox.append(.data(Wire.frame(runs, seq: frames.sent)))
			return
		}
		
		let runs = FrameStream.changes(from: UnsafeBufferPointer(start: stage_source(stage) + 1, count: Universe.channelCount), to: universe.values)
		guard !runs.isEmpty else { return }
		let bytes = [UInt8](Wire.frame(runs, seq: 0))
		stage_write(stage, bytes, bytes.count, UInt8(Self.ownClient))
	}
	
	private func advance() {
		flush()
		let restated = stage_tick(stage, now)
		let count = stage_frame(stage, UInt8(Self.ownClient), false, &scratch, scratch.count)
		
		if count > 0, let (_, runs) = Wire.runs(in: Array(scratch.prefix(count))) {
			var next = universe
			
			for run in runs {
				next.set(run.values, at: run.start)
			}
			
			universe = next
		}
		
		if restated { announce() }
		guard running == nil, stage_busy(stage) else { return }
		
		running = Task { [weak self] in
			while let self, stage_busy(stage), !Task.isCancelled {
				try? await Task.sleep(for: .milliseconds(10))
				advance()
			}
			
			self?.running = nil
		}
	}
	
	private func announce() {
		var state = [UInt8](repeating: 0, count: stage_state(stage, now, nil, 0))
		let count = stage_state(stage, now, &state, state.count)
		state[1] = UInt8(Self.ownClient)
		state[2] = UInt8(sent & 0xFF)
		state[3] = UInt8(sent >> 8)
		take(Array(state.prefix(count)))
	}
	
	func applyPatch(_ fixtures: [Fixture], library: FixtureLibrary) {
		if !hasLoadedPatch, !library.types.isEmpty {
			hasLoadedPatch = true
			
			if !hasAdoptedSource {
				universe = Universe()
				active = [:]
				defaulted = []
				
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
			active[address] = nil
			defaulted.remove(address)
		}
		
		patched = covered
		selection.keep(Set(fixtures.map(\.identifier)))
		
		cover(max(covered.max() ?? 0, Universe.minimumSlots))
		
		var writer = ByteWriter()
		writer.byte(Wire.mapOpcode)
		
		for fixture in fixtures {
			library.type(fixture.typeID)?.map(at: fixture.start, into: &writer)
		}
		
		guard writer.data != map else { return }
		map = writer.data
		let bytes = [UInt8](map)
		stage_map(stage, bytes, bytes.count)
		post(.data(map))
	}
	
	var output: [UInt8] {
		var values = universe.values
		stage_scale(stage, &values)
		return values
	}
	
	private func tick() {
		guard !isMuted else {
			advance()
			return
		}
		
		guard isSynced else { return }
		
		if master != announcedMaster {
			announcedMaster = master
			outbox.append(Wire.Command.master(master).message)
		}
		
		if blackout != announcedBlackout {
			announcedBlackout = blackout
			outbox.append(Wire.Command.blackout(blackout).message)
		}
		
		flush()
		drain()
	}
	
	private func post(_ message: URLSessionWebSocketTask.Message) {
		guard !isMuted else { return }
		outbox.append(message)
		drain()
	}
	
	private func drain() {
		guard draining == nil, isSynced else { return }
		
		draining = Task {
			while isSynced, !outbox.isEmpty {
				await connection.send(outbox.removeFirst())
			}
			
			draining = nil
		}
	}
}
