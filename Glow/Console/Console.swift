import Observation
import SwiftData
import SwiftUI

@Observable
final class Console {
	private(set) var universe = Universe()
	
	private(set) var link: LinkState = .offline
	private(set) var node: Wire.NodeInfo?
	private(set) var usage: Wire.Usage?
	private(set) var playback = Playback()
	
	let selection = Selection()
	let access: Access
	let notices: AsyncStream<Wire.Notice>
	
	var master: Double = 1 {
		didSet { level() }
	}
	
	var blackout = false {
		didSet { level() }
	}
	
	var isMuted = false {
		didSet {
			guard oldValue, !isMuted else { return }
			connect()
		}
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
	
	var status: LinkState {
		isMuted && !link.isConnected ? .offline : link
	}
	
	var network: String {
		guard link.isConnected, let node else { return status.name }
		return node.wifi.isEmpty ? ControllerWiFi.name : node.wifi
	}
	
	private(set) var active: [Int: UInt8] = [:]
	private var defaulted: Set<Int> = []
	private(set) var patched: Set<Int> = []
	private(set) var span = Universe.minimumSlots
	private(set) var resets = 0
	private(set) var commands = 0
	
	private let connection: NodeLink
	private let noticer: AsyncStream<Wire.Notice>.Continuation
	private let stage = stage_new()!
	private let born = ContinuousClock.now
	private var outbox: [Wire.Message] = []
	private var draining: Task<Void, Never>?
	private var isSynced = false
	private var events: Task<Void, Never>?
	private var frames = FrameStream()
	private var scratch = [UInt8](repeating: 0, count: Int(STAGE_FRAME_MAX))
	private var map = Data([Wire.mapOpcode])
	private var announcedMaster: Double?
	private var announcedBlackout: Bool?
	private var hasAdoptedSource = false
	private var hasLoadedPatch = false
	private var running: Task<Void, Never>?
	private var sent = 0
	private var acked = 0
	private var commanded = ContinuousClock.now
	private var continued: [String: String] = [:]
	
	private static let endpointKey = "node.endpoint"
	private static let addressKey = "node.address"
	private static let ownClient = 0
	private static let ackPatience = Duration.seconds(1)
	
	init() {
		(notices, noticer) = AsyncStream<Wire.Notice>.makeStream()
		let connection = NodeLink()
		self.connection = connection
		access = Access(connection: connection)
		
		if let data = UserDefaults.standard.data(forKey: Self.endpointKey), let stored = try? JSONDecoder().decode(NodeEndpoint.self, from: data) {
			endpoint = stored
			isConfigured = true
		} else {
			endpoint = .fallback
		}
		
		access.post = { [weak self] command in
			self?.send(command)
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
			let changes = Observations<(Universe, Bool, Bool, Double, Bool), Never>.untilFinished { [weak self] in
				guard let self else { return .finish }
				return .next((universe, isMuted, isSynced, master, blackout))
			}
			
			for await _ in changes {
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
			guard !isMuted else { return }
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
			
			if !info.hasSource {
				isSynced = true
			} else if !isMuted {
				master = info.master
				blackout = info.blackout
				announcedMaster = info.master
				announcedBlackout = info.blackout
			}
			
			access.admit()
		case let .locked(challenge): access.challenge(challenge)
		case let .password(isSet):
			node?.hasPassword = isSet
			access.protected(id: node?.id ?? "")
		case let .passwordRefused(outcome): access.refused(outcome)
		case let .usage(value):
			usage = value
		case let .frame(ack, runs):
			guard !isMuted else { return }
			frames.adopt(runs, ack: ack, into: &universe)
			guard runs.count == 1, runs[0].start.value == 1, runs[0].values.count == Universe.channelCount else { return }
			hasAdoptedSource = true
			isSynced = true
		case let .master(level):
			guard !isMuted else { return }
			master = level
			announcedMaster = level
		case let .blackout(on):
			guard !isMuted else { return }
			blackout = on
			announcedBlackout = on
		case let .playback(state):
			guard !isMuted else { return }
			take(state)
		case let .notice(notice):
			noticer.yield(notice)
		}
	}
	
	private func cover(_ reach: Int) {
		guard reach != span else { return }
		span = reach
		frames.cover(reach)
		post(Wire.Command.span(reach).message)
	}
	
	private func level() {
		stage_levels(stage, Float(master), blackout)
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
		let copy = Fixture(typeID: fixture.typeID, name: Identifier.unusedName(fixture.name, among: fixtures.map(\.name)), address: DMXAddress(clamping: fixture.address + width), sortIndex: Ordering.nextSortIndex(fixtures, sortIndex: \.sortIndex))
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
		var index = Ordering.nextSortIndex(fixtures, sortIndex: \.sortIndex)
		
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
	
	func isCovered(beyond depth: Int = 0) -> Bool {
		guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene, var top = scene.keyWindow?.rootViewController else { return false }
		var covers = 0
		
		while let next = top.presentedViewController {
			covers += 1
			top = next
		}
		
		return covers > depth
	}
	
	func press(_ action: SceneAction, on list: CueList, depth: Int) {
		guard !isCovered(beyond: depth) else { return }
		run(action, on: list)
	}
	
	func toggle(_ list: CueList) {
		guard list.index(of: playback.cue(of: list.scene)) == nil else {
			stop(list)
			return
		}
		
		go(list)
	}
	
	func shownScene(among scenes: [String]) -> String? {
		([selection.scene].compactMap { $0 } + playback.order.filter { !playback.isFlashing($0) }.reversed()).first(where: scenes.contains)
	}
	
	func stopAll() {
		for entry in playback.playing.reversed() {
			stop(entry.scene, fade: lists[entry.scene]?.fade(of: entry.cue) ?? 0)
		}
	}
	
	func flash(_ list: CueList, isHeld: Bool) {
		guard isHeld else {
			guard playback.isFlashing(list.scene) else { return }
			playback.flash(list.scene, false)
			stop(list, snapping: true)
			return
		}
		
		guard playback.cue(of: list.scene) == nil, !list.cues.isEmpty else { return }
		play(list, at: 0, snapping: true)
		playback.flash(list.scene, true)
	}
	
	func go(_ list: CueList) {
		guard let index = upcoming(list) else { return }
		play(list, at: index)
	}
	
	func arm(_ cue: String, of scene: String) {
		playback.arm(playback.armed(of: scene) == cue ? nil : cue, of: scene)
	}
	
	func upcoming(_ list: CueList) -> Int? {
		list.index(of: playback.armed(of: list.scene)) ?? list.next(after: list.index(of: playback.cue(of: list.scene)))
	}
	
	func back(_ list: CueList) {
		guard let current = list.index(of: playback.cue(of: list.scene)), let index = list.previous(before: current) else { return }
		play(list, at: index)
	}
	
	func play(_ list: CueList, at index: Int, snapping: Bool = false) {
		guard list.cues.indices.contains(index), command(.play, scene: list.scene, body: list.program(from: index, snapping: snapping)) else { return }
		let cue = list.cues[index]
		let start = Date.now.addingTimeInterval(cue.delay)
		if !snapping { selection.follow(list.scene, isIdle: selection.scene.map { playback.cue(of: $0) == nil } ?? false) }
		playback.play(cue.identifier, of: list.scene, fade: snapping ? Fade(start: .now, end: .now, follows: false) : Fade(start: start, end: start.addingTimeInterval(cue.fade)))
		playback.arm(nil, of: list.scene)
	}
	
	func land(_ list: CueList, at index: Int) {
		guard list.cues.indices.contains(index), command(.land, scene: list.scene, body: list.program(from: index, snapping: list.cues[index].follow == nil)) else { return }
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
	
	func move(_ chosen: [Cue], from list: CueList, to look: Look, among cues: [Cue]) {
		let picked = Set(chosen.map(\.identifier))
		release(picked, from: list)
		let start = (look.cues(among: cues).last?.sortIndex ?? 0).rounded(.down) + 1
		
		for (offset, cue) in chosen.enumerated() {
			cue.lookID = look.identifier
			cue.sortIndex = start + Double(offset)
		}
	}
	
	private func release(_ gone: Set<String>, from list: CueList) {
		if let marked = selection.marked, gone.contains(marked), let index = list.index(of: marked) {
			let before = list.cues[..<index].last { !gone.contains($0.identifier) }
			let after = list.cues[index...].first { !gone.contains($0.identifier) }
			selection.marked = (before ?? after)?.identifier
		}
		
		if let armed = playback.armed(of: list.scene), gone.contains(armed) {
			playback.arm(nil, of: list.scene)
		}
		
		guard let live = playback.cue(of: list.scene), gone.contains(live), let index = list.index(of: live) else { return }
		let trimmed = gone.reduce(list) { $0.removing($1) }
		
		guard let first = trimmed.cues.first else {
			stop(list)
			return
		}
		
		let landing = list.cues[..<index].last { !gone.contains($0.identifier) } ?? first
		play(trimmed, at: trimmed.index(of: landing.identifier) ?? 0, snapping: landing.follow == nil)
	}
	
	func remove(_ look: Look, with cues: [Cue], context: ModelContext) {
		stop(look.identifier, fade: lists[look.identifier]?.fade(of: playback.cue(of: look.identifier)) ?? 0)
		look.remove(with: cues, context: context)
	}
	
	func isMoving(_ scene: String) -> Bool {
		guard let fade = playback.fade(of: scene) else { return false }
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
			play(list, at: index, snapping: list.cues[index].follow == nil)
		} else {
			stop(look.identifier, fade: 0)
		}
	}
	
	private func stop(_ scene: String, fade: Double) {
		guard playback.cue(of: scene) != nil else { return }
		var writer = ByteWriter()
		writer.number(CueList.milliseconds(fade))
		guard command(.stop, scene: scene, body: writer.data) else { return }
		playback.stop(scene, fade: fade)
	}
	
	@discardableResult private func command(_ action: Wire.Action, scene: String, body: Data) -> Bool {
		guard isMuted || link.isConnected else { return false }
		sent = (sent + 1) & 0xFFFF
		commanded = .now
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
		if ContinuousClock.now - commanded > Self.ackPatience { acked = sent }
		guard acked == sent, playback.adopt(state, at: .now) else { return }
		continued = continued.filter { scene, cue in playback.playing.contains { $0.scene == scene && $0.cue == cue && $0.wants && $0.caller != 0xFF } }
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
	
	private func post(_ message: Wire.Message) {
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
