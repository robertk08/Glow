import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class ShowLibrary {
	private(set) var shows: [Show] = []
	private(set) var activeID = ""
	private(set) var isLoaded = false
	private(set) var isDemo = false {
		didSet { console?.isMuted = isDemo }
	}
	private(set) var canUndo = false
	var refusal: Refusal?
	let container = ShowLibrary.store()
	
	private let store = NodeStore()
	private let decoder = JSONDecoder()
	
	private var console: Console?
	private var types: FixtureLibrary?
	private var endpoint: NodeEndpoint?
	private var client: Int?
	private var latest: ShowList?
	private var demo = ShowList(active: "", shows: [])
	private var held: [String: ShowContents] = [:]
	private var loadedID = ""
	private var isCurrent = false
	private var epoch = 0
	private var baseline: [String: Data] = [:]
	private var sent: [String: Data] = [:]
	private var deferred: Set<String> = []
	private var waiting: Set<NodeStore.Folder> = []
	private var touched: Set<PersistentIdentifier> = []
	private var pruned: Set<NodeStore.Folder> = []
	private var lastSync = Date.distantPast
	private var isSettled = false
	private var queue: Task<Void, Never>?
	private var pending: Task<Void, Never>?
	private var retry: Task<Void, Never>?
	private var dropping: Task<Void, Never>?
	private var listening: Task<Void, Never>?
	
	nonisolated static let everything = Set(NodeStore.Folder.allCases)
	private static let nothing = Show(name: "")
	private static let frameLimit = 12000
	private static let coalesce: TimeInterval = 0.25
	private static let commitEvery: Duration = .milliseconds(100)
	
	init() {
		decoder.dateDecodingStrategy = .iso8601
		
		Task { [weak self] in
			try? await Task.sleep(for: .milliseconds(1500))
			self?.isSettled = true
		}
		
		Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: ShowLibrary.commitEvery)
				self?.commit()
			}
		}
		
		Task { [weak self] in
			for await note in NotificationCenter.default.notifications(named: ModelContext.didSave) {
				let (folders, touched) = Self.changes(in: note)
				self?.saved(folders, touched: touched)
			}
		}
	}
	
	var active: Show {
		shows.first { $0.id == activeID } ?? Self.nothing
	}
	
	var standby: Standby {
		guard !isLoaded else { return .ready }
		guard isSettled, let console else { return .starting }
		guard !console.link.isConnected else { return .starting }
		guard console.link != .locked else { return .locked }
		guard console.isConfigured else { return .welcome }
		return .searching
	}
	
	func reach(_ console: Console, library: FixtureLibrary) {
		self.console = console
		types = library
		endpoint = console.reachable
		client = console.node?.client
		
		if listening == nil {
			listening = Task { [weak self] in
				for await notice in console.notices {
					self?.receive(notice)
				}
			}
		}
		
		guard console.link.isConnected else {
			latest = nil
			guard !isDemo else { return }
			isCurrent = false
			held = [:]
			sent = [:]
			deferred = []
			retry?.cancel()
			guard isLoaded, dropping == nil else { return }
			
			dropping = Task {
				try? await Task.sleep(for: .seconds(2))
				guard !Task.isCancelled else { return }
				unload()
			}
			return
		}
		
		dropping?.cancel()
		dropping = nil
		stopDemo()
	}
	
	func startDemo() {
		guard !isDemo else { return }
		guard let url = Bundle.main.url(forResource: "Demo", withExtension: "json") else { return }
		guard let data = try? Data(contentsOf: url), let file = try? decoder.decode(ShowFile.self, from: data), file.isReadable else { return }
		
		let show = Show(name: file.name)
		held = [show.id: file.show]
		demo = ShowList(active: show.id, shows: [show])
		isDemo = true
		follow()
	}
	
	func settle(_ phase: ScenePhase) {
		guard phase != .active, isLoaded, !isDemo else { return }
		
		enqueue {
			await self.synchronise(Self.everything)
		}
	}
	
	func activate(_ show: Show) {
		guard show.id != activeID else { return }
		change(.openShow(show.id))
	}
	
	func create(name: String) {
		change(.addShow(Show(name: Identifier.unusedName(name, among: shows.map(\.name)))))
	}
	
	func duplicate(_ show: Show) {
		enqueue {
			var copy = show.id == self.loadedID ? self.contents() : self.held[show.id]
			
			if copy == nil, !self.isDemo, let endpoint = self.endpoint {
				copy = await self.store.show(show.id, at: endpoint)
			}
			
			guard let copy else { return }
			self.adopt(copy, named: show.name)
		}
	}
	
	func rename(_ show: Show, to name: String) {
		var renamed = show
		renamed.name = Show.fitted(name)
		change(.renameShow(renamed))
	}
	
	func delete(_ show: Show) {
		guard shows.count > 1 else { return }
		held[show.id] = nil
		change(.removeShow(show.id))
	}
	
	func contents(_ folders: Set<NodeStore.Folder> = everything, only identifier: String? = nil) -> ShowContents {
		let context = container.mainContext
		var show = ShowContents()
		var fixtures: [Fixture] = []
		
		if !folders.isDisjoint(with: [.lights, .made]) { fixtures = (try? context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		if folders.contains(.lights) { show.lights = fixtures.map(\.entry) }
		if folders.contains(.groups) { show.groups = ((try? context.fetch(FetchDescriptor<FixtureGroup>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []).map(\.entry) }
		
		if folders.contains(.scenes) {
			var looks = FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)])
			if let identifier { looks.predicate = #Predicate { $0.identifier == identifier } }
			show.scenes = ((try? context.fetch(looks)) ?? []).map(\.entry)
		}
		
		if folders.contains(.cues) {
			var cues = FetchDescriptor<Cue>(sortBy: [SortDescriptor(\.sortIndex)])
			if let identifier { cues.predicate = #Predicate { $0.identifier == identifier } }
			show.cues = ((try? context.fetch(cues)) ?? []).map(\.entry)
		}
		
		if folders.contains(.made) {
			show.made = ((try? context.fetch(FetchDescriptor<StoredFixtureType>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []).map(\.definition)
			
			for fixture in fixtures where !show.made.contains(where: { $0.id == fixture.typeID }) {
				guard let definition = types?.type(fixture.typeID) else { continue }
				show.made.append(definition)
			}
		}
		
		guard let identifier else { return show }
		show.lights.removeAll { $0.identifier != identifier }
		show.groups.removeAll { $0.identifier != identifier }
		show.made.removeAll { $0.id != identifier }
		return show
	}
	
	func exportable() -> ShowFile {
		ShowFile(name: active.name, show: contents())
	}
	
	func adopt(contentsOf url: URL) -> Bool {
		let isScoped = url.startAccessingSecurityScopedResource()
		defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
		guard let data = try? Data(contentsOf: url), let file = try? decoder.decode(ShowFile.self, from: data), file.isReadable else { return false }
		adopt(file.show, named: file.name)
		return true
	}
	
	@discardableResult private func enqueue<Result: Sendable>(_ work: @escaping @MainActor () async -> Result) -> Task<Result, Never> {
		let previous = queue
		let next = Task {
			await previous?.value
			return await work()
		}
		
		queue = Task {
			_ = await next.value
		}
		
		return next
	}
	
	private var list: ShowList? {
		isDemo ? demo : latest
	}
	
	private func change(_ command: Wire.Command) {
		if isDemo {
			demo.apply(command)
		} else {
			latest?.apply(command)
			console?.send(command)
		}
		
		follow()
	}
	
	private func adopt(_ contents: ShowContents, named name: String) {
		let show = Show(name: Identifier.unusedName(name, among: shows.map(\.name)))
		held[show.id] = contents
		change(.addShow(show))
	}
	
	func stopDemo() {
		guard isDemo else { return }
		unload()
		isDemo = false
		held = [:]
		follow()
	}
	
	private func follow() {
		guard let list else { return }
		shows = list.shows
		activeID = list.activeShow?.id ?? ""
		
		enqueue {
			await self.open()
		}
	}
	
	private func open() async {
		guard let show = list?.activeShow, !isLoaded || !isCurrent || show.id != loadedID else { return }
		
		if isLoaded, isCurrent, loadedID != show.id {
			if isDemo {
				held[loadedID] = contents()
			} else {
				await synchronise(Self.everything)
			}
		}
		
		let started = epoch
		let isArriving = held[show.id] != nil && !isDemo
		var incoming = held[show.id] ?? (isDemo ? ShowContents() : nil)
		
		if incoming == nil, let endpoint {
			incoming = await store.show(show.id, at: endpoint)
		}
		
		guard started == epoch, list?.activeShow?.id == show.id else { return }
		
		guard let incoming else {
			unload()
			
			retry = Task {
				try? await Task.sleep(for: .seconds(2))
				guard !Task.isCancelled else { return }
				follow()
			}
			return
		}
		
		if !loadedID.isEmpty, loadedID != show.id {
			console?.closeShow()
		}
		
		if isArriving { held[show.id] = nil }
		loadedID = show.id
		fill(with: incoming)
		isLoaded = true
		isCurrent = true
		
		guard isArriving else {
			changed([.lights, .groups, .made], pruned: [.scenes, .cues])
			return
		}
		
		baseline = [:]
		changed(Self.everything)
	}
	
	private func receive(_ notice: Wire.Notice) {
		switch notice {
		case let .shows(list):
			latest = list
			follow()
		case let .refused(reason):
			refusal = reason
		default:
			guard !isDemo else { return }
			
			enqueue {
				await self.accept(notice)
			}
		}
	}
	
	private func reject() {
		refusal = .storage
		isCurrent = false
		follow()
	}
	
	private func accept(_ notice: Wire.Notice) async {
		guard let endpoint else { return }
		
		switch notice {
		case .shows, .refused:
			return
		case let .landed(place, isWritten):
			guard isCurrent, place.show == loadedID, let folder = NodeStore.Folder(rawValue: place.folder) else { return }
			let data = sent.removeValue(forKey: place.key)
			
			guard isWritten else {
				reject()
				return
			}
			
			if let data {
				baseline[place.key] = data.isEmpty ? nil : data
			}
			
			guard deferred.remove(place.key) != nil else { return }
			let identifier = place.id
			
			switch folder {
			case .scenes: changed([], touched: Set(((try? container.mainContext.fetch(FetchDescriptor<Look>(predicate: #Predicate { $0.identifier == identifier }))) ?? []).map(\.persistentModelID)), pruned: [folder])
			case .cues: changed([], touched: Set(((try? container.mainContext.fetch(FetchDescriptor<Cue>(predicate: #Predicate { $0.identifier == identifier }))) ?? []).map(\.persistentModelID)), pruned: [folder])
			case .lights, .groups, .made: changed([folder])
			}
		case let .stored(place, body):
			guard let folder = accepts(place) else { return }
			var data = body
			
			if data == nil {
				data = await store.object(folder, id: place.id, in: place.show, at: endpoint)
			}
			
			guard let data, accepts(place) != nil else { return }
			take(data, at: place, in: folder)
		case let .erased(place):
			guard let folder = accepts(place) else { return }
			take(nil, at: place, in: folder)
		}
	}
	
	private func accepts(_ place: Wire.Place) -> NodeStore.Folder? {
		guard isLoaded, isCurrent, !isDemo, place.show == loadedID, sent[place.key] == nil else { return nil }
		return NodeStore.Folder(rawValue: place.folder)
	}
	
	private func take(_ data: Data?, at place: Wire.Place, in folder: NodeStore.Folder) {
		let related: Set<NodeStore.Folder> = switch folder {
		case .groups: [.lights]
		case .lights: [.made]
		case .made, .scenes, .cues: []
		}
		let before = Self.encoded(contents(related), folders: related)
		
		if let data {
			let single = ShowContents(objects: [(place.folder, place.id, data)])
			guard single.unreadable.isEmpty else { return }
			merge(single)
		} else {
			remove(folder, identifier: place.id)
		}
		
		let after = Self.encoded(contents(related), folders: related)
		baseline[place.key] = Self.encoded(contents([folder], only: place.id), folders: [folder])[place.key]
		
		for (other, fresh) in after where before[other] != fresh {
			baseline[other] = fresh
		}
		
		for other in before.keys where after[other] == nil {
			baseline[other] = nil
		}
	}
	
	private func commit() {
		guard isLoaded else { return }
		let context = container.mainContext
		guard context.hasChanges else { return }
		try? context.save()
	}
	
	private func saved(_ folders: Set<NodeStore.Folder>, touched: Set<PersistentIdentifier>?) {
		let context = container.mainContext
		canUndo = context.undoManager?.canUndo == true
		
		if let types, !folders.isDisjoint(with: [.lights, .made, .scenes, .cues]) {
			let fixtures = (try? context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
			
			if !folders.isDisjoint(with: [.lights, .made]) {
				types.setMade(((try? context.fetch(FetchDescriptor<StoredFixtureType>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []).map(\.definition))
				console?.applyPatch(fixtures, library: types)
			}
			
			let lists = CueList.all((try? context.fetch(FetchDescriptor<Look>())) ?? [], cues: (try? context.fetch(FetchDescriptor<Cue>())) ?? [], fixtures: fixtures)
			console?.lists = Dictionary(lists.map { ($0.scene, $0) }, uniquingKeysWith: { first, _ in first })
		}
		
		guard let touched else {
			changed(folders)
			return
		}
		
		changed(folders.subtracting([.scenes, .cues]), touched: touched, pruned: folders.intersection([.scenes, .cues]))
	}
	
	private func merge(_ incoming: ShowContents) {
		let context = container.mainContext
		context.undoManager?.disableUndoRegistration()
		defer { context.undoManager?.enableUndoRegistration() }
		
		var groups = Dictionary(((try? context.fetch(FetchDescriptor<FixtureGroup>())) ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
		let fixtures = Dictionary(((try? context.fetch(FetchDescriptor<Fixture>())) ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
		let made = Dictionary(((try? context.fetch(FetchDescriptor<StoredFixtureType>())) ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
		let lookIDs = incoming.scenes.map(\.identifier)
		let cueIDs = incoming.cues.map(\.identifier)
		let looks = Dictionary((lookIDs.isEmpty ? [] : (try? context.fetch(FetchDescriptor<Look>(predicate: #Predicate { lookIDs.contains($0.identifier) }))) ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
		let cues = Dictionary((cueIDs.isEmpty ? [] : (try? context.fetch(FetchDescriptor<Cue>(predicate: #Predicate { cueIDs.contains($0.identifier) }))) ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
		let shipped = Set((types?.builtIn ?? []).map(\.id))
		
		for entry in incoming.groups {
			let group = groups[entry.identifier] ?? FixtureGroup(name: entry.name, sortIndex: entry.sortIndex)
			if group.modelContext == nil { context.insert(group) }
			group.take(entry)
			groups[entry.identifier] = group
		}
		
		for entry in incoming.lights {
			guard let address = DMXAddress(entry.address) else { continue }
			let fixture = fixtures[entry.identifier] ?? Fixture(typeID: entry.typeID, name: entry.name, address: address, sortIndex: entry.sortIndex)
			if fixture.modelContext == nil { context.insert(fixture) }
			fixture.take(entry, groups: Array(groups.values))
		}
		
		for entry in incoming.made where !shipped.contains(entry.id) {
			let stored = made[entry.id] ?? StoredFixtureType(entry)
			if stored.modelContext == nil { context.insert(stored) }
			stored.definition = entry
		}
		
		for entry in incoming.scenes {
			let look = looks[entry.identifier] ?? Look(name: entry.name, sortIndex: entry.sortIndex)
			if look.modelContext == nil { context.insert(look) }
			look.take(entry)
		}
		
		for entry in incoming.cues {
			let cue = cues[entry.identifier] ?? Cue(lookID: entry.scene, sortIndex: entry.sortIndex, fade: entry.fade, levels: Levels())
			if cue.modelContext == nil { context.insert(cue) }
			cue.take(entry)
		}
		
		try? context.save()
	}
	
	private func remove(_ folder: NodeStore.Folder, identifier: String) {
		let context = container.mainContext
		context.undoManager?.disableUndoRegistration()
		defer { context.undoManager?.enableUndoRegistration() }
		
		switch folder {
		case .lights: discard(#Predicate<Fixture> { $0.identifier == identifier })
		case .groups: discard(#Predicate<FixtureGroup> { $0.identifier == identifier })
		case .made: discard(#Predicate<StoredFixtureType> { $0.identifier == identifier })
		case .scenes: discard(#Predicate<Look> { $0.identifier == identifier })
		case .cues: discard(#Predicate<Cue> { $0.identifier == identifier })
		}
		
		try? context.save()
	}
	
	private func unload() {
		retry?.cancel()
		retry = nil
		guard isLoaded else { return }
		
		epoch += 1
		isLoaded = false
		isCurrent = false
		shows = []
		activeID = ""
		loadedID = ""
		baseline = [:]
		sent = [:]
		deferred = []
		waiting = []
		clear()
		console?.closeShow(keepingLook: isDemo)
	}
	
	private func fill(with incoming: ShowContents) {
		merge(incoming)
		prune(keeping: incoming)
		container.mainContext.undoManager?.removeAllActions()
		sent = [:]
		deferred = []
		baseline = incoming.originals
		
		for key in incoming.unreadable {
			baseline[key] = Data()
		}
	}
	
	private func changed(_ folders: Set<NodeStore.Folder>, touched: Set<PersistentIdentifier> = [], pruned: Set<NodeStore.Folder> = []) {
		guard isLoaded, !isDemo, !folders.isEmpty || !touched.isEmpty || !pruned.isEmpty else { return }
		waiting.formUnion(folders)
		self.touched.formUnion(touched)
		self.pruned.formUnion(pruned)
		guard pending == nil else { return }
		let delay = Self.coalesce - Date().timeIntervalSince(lastSync)
		
		pending = Task {
			if delay > 0 {
				try? await Task.sleep(for: .seconds(delay))
			}
			
			pending = nil
			
			enqueue {
				let folders = self.waiting
				let touched = self.touched
				let pruned = self.pruned
				self.waiting = []
				self.touched = []
				self.pruned = []
				self.lastSync = Date()
				await self.synchronise(folders, touched: touched, pruned: pruned)
			}
		}
	}
	
	private func synchronise(_ folders: Set<NodeStore.Folder>, touched: Set<PersistentIdentifier> = [], pruned: Set<NodeStore.Folder> = []) async {
		guard isLoaded, isCurrent, !isDemo else { return }
		
		let context = container.mainContext
		let showID = loadedID
		var current = folders.isEmpty ? [:] : await Self.snapshot(of: contents(folders), folders: folders)
		guard showID == loadedID, isCurrent else { return }
		var present: [NodeStore.Folder: Set<String>] = [:]
		
		for folder in folders {
			present[folder] = Set(current.keys.compactMap { Self.split($0).flatMap { $0.0 == folder ? $0.1 : nil } })
		}
		
		for id in touched {
			switch id.entityName {
			case "Look": if !folders.contains(.scenes), let look: Look = context.registeredModel(for: id), !look.isGone { current["\(NodeStore.Folder.scenes.rawValue)/\(look.identifier)"] = look.entry.body }
			case "Cue": if !folders.contains(.cues), let cue: Cue = context.registeredModel(for: id), !cue.isDeleted { current["\(NodeStore.Folder.cues.rawValue)/\(cue.identifier)"] = cue.entry.body }
			default: break
			}
		}
		
		if pruned.contains(.scenes), !folders.contains(.scenes) {
			var looks = FetchDescriptor<Look>()
			looks.propertiesToFetch = [\.identifier]
			present[.scenes] = Set(((try? context.fetch(looks)) ?? []).map(\.identifier))
		}
		
		if pruned.contains(.cues), !folders.contains(.cues) {
			var cues = FetchDescriptor<Cue>()
			cues.propertiesToFetch = [\.identifier]
			present[.cues] = Set(((try? context.fetch(cues)) ?? []).map(\.identifier))
		}
		
		var changes = current.filter { baseline[$0.key] != $0.value }
		
		for key in baseline.keys {
			guard let (folder, identifier) = Self.split(key), let ids = present[folder], !ids.contains(identifier) else { continue }
			changes[key] = Data()
		}
		
		for (key, data) in changes {
			guard let (folder, identifier) = Self.split(key) else { continue }
			
			guard sent[key] == nil else {
				deferred.insert(key)
				continue
			}
			
			sent[key] = data
			
			if data.count <= Self.frameLimit {
				console?.send(document: Wire.document(show: showID, folder: folder.rawValue, id: identifier, body: data.isEmpty ? nil : data))
				continue
			}
			
			guard let endpoint else { continue }
			let place = Wire.Place(show: showID, folder: folder.rawValue, id: identifier)
			let client = client
			
			Task {
				let isStored = await store.put(data, folder: folder, id: identifier, in: showID, at: endpoint, client: client)
				receive(.landed(place, isStored))
			}
		}
	}
	
	@concurrent nonisolated static func snapshot(of contents: ShowContents, folders: Set<NodeStore.Folder> = everything) async -> [String: Data] {
		encoded(contents, folders: folders)
	}
	
	nonisolated static func encoded(_ contents: ShowContents, folders: Set<NodeStore.Folder>) -> [String: Data] {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		var out: [String: Data] = [:]
		
		if folders.contains(.lights) {
			for light in contents.lights {
				out["\(NodeStore.Folder.lights.rawValue)/\(light.identifier)"] = try? encoder.encode(light)
			}
		}
		
		if folders.contains(.groups) {
			for group in contents.groups {
				out["\(NodeStore.Folder.groups.rawValue)/\(group.identifier)"] = try? encoder.encode(group)
			}
		}
		
		if folders.contains(.made) {
			for made in contents.made {
				out["\(NodeStore.Folder.made.rawValue)/\(made.id)"] = try? encoder.encode(made)
			}
		}
		
		if folders.contains(.scenes) {
			for scene in contents.scenes {
				out["\(NodeStore.Folder.scenes.rawValue)/\(scene.identifier)"] = scene.body
			}
		}
		
		if folders.contains(.cues) {
			for cue in contents.cues {
				out["\(NodeStore.Folder.cues.rawValue)/\(cue.identifier)"] = cue.body
			}
		}
		
		return out
	}
	
	nonisolated static func changes(in note: Notification) -> (folders: Set<NodeStore.Folder>, touched: Set<PersistentIdentifier>?) {
		guard let info = note.userInfo else { return (everything, nil) }
		
		var found: Set<NodeStore.Folder> = []
		var touched: Set<PersistentIdentifier> = []
		var sawKey = false
		
		for key in [ModelContext.NotificationKey.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers] {
			guard let ids = info[key.rawValue] as? [PersistentIdentifier] ?? info[key] as? [PersistentIdentifier] else { continue }
			sawKey = true
			
			for id in ids {
				switch id.entityName {
				case "Fixture": found.formUnion([.lights, .made])
				case "FixtureGroup": found.insert(.groups)
				case "StoredFixtureType": found.insert(.made)
				case "Look": found.insert(.scenes)
				case "Cue": found.insert(.cues)
				default: break
				}
				
				if key != .deletedIdentifiers, ["Look", "Cue"].contains(id.entityName) { touched.insert(id) }
			}
		}
		
		return sawKey ? (found, touched) : (everything, nil)
	}
	
	nonisolated private static func split(_ key: String) -> (NodeStore.Folder, String)? {
		let parts = key.split(separator: "/", maxSplits: 1)
		guard parts.count == 2, let folder = NodeStore.Folder(rawValue: String(parts[0])) else { return nil }
		return (folder, String(parts[1]))
	}
	
	private func prune(keeping show: ShowContents) {
		let context = container.mainContext
		let lights = show.lights.map(\.identifier)
		let groups = show.groups.map(\.identifier)
		let made = show.made.map(\.id)
		let scenes = show.scenes.map(\.identifier)
		let cues = show.cues.map(\.identifier)
		context.undoManager?.disableUndoRegistration()
		defer { context.undoManager?.enableUndoRegistration() }
		
		discard(#Predicate<Fixture> { !lights.contains($0.identifier) })
		discard(#Predicate<FixtureGroup> { !groups.contains($0.identifier) })
		discard(#Predicate<StoredFixtureType> { !made.contains($0.identifier) })
		discard(#Predicate<Look> { !scenes.contains($0.identifier) })
		discard(#Predicate<Cue> { !cues.contains($0.identifier) })
		try? context.save()
	}
	
	private func discard<Model: PersistentModel>(_ predicate: Predicate<Model>) {
		let context = container.mainContext
		
		for model in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
			context.delete(model)
		}
	}
	
	private func clear() {
		prune(keeping: ShowContents())
		container.mainContext.undoManager?.removeAllActions()
	}
	
	private static func store() -> ModelContainer {
		let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
		let container = try! ModelContainer(for: Fixture.self, FixtureGroup.self, StoredFixtureType.self, Look.self, Cue.self, configurations: configuration)
		container.mainContext.undoManager = UndoManager()
		container.mainContext.autosaveEnabled = true
		return container
	}
}
