import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class ShowLibrary {
	private(set) var shows: [Show] = []
	private(set) var activeID = ""
	private(set) var isLoaded = false
	private(set) var isDemo = false
	private(set) var canUndo = false
	let container = ShowLibrary.store()
	
	private let store = NodeStore()
	private let decoder = JSONDecoder()
	
	private var console: Console?
	private var types: FixtureLibrary?
	private var endpoint: NodeEndpoint?
	private var client: Int?
	private var loadedID = ""
	private var epoch = 0
	private var baseline: [String: Data] = [:]
	private var sent: [String: Data] = [:]
	private var deferred: Set<String> = []
	private var waiting: Set<NodeStore.Folder> = []
	private var lastSync = Date.distantPast
	private var wasConnected = false
	private var isSettled = false
	private var queue: Task<Void, Never>?
	private var pending: Task<Void, Never>?
	private var loading: Task<Void, Never>?
	private var dropping: Task<Void, Never>?
	private var listening: Task<Void, Never>?
	private var settling: Task<Void, Never>?
	private var saves: Task<Void, Never>?
	private var commits: Task<Void, Never>?
	
	nonisolated static let everything = Set(NodeStore.Folder.allCases)
	private static let nothing = Show(name: "")
	private static let frameLimit = 12000
	private static let coalesce: TimeInterval = 0.25
	private static let commitEvery: Duration = .milliseconds(100)
	
	init() {
		decoder.dateDecodingStrategy = .iso8601
		
		settling = Task { [weak self] in
			try? await Task.sleep(for: .milliseconds(1500))
			self?.isSettled = true
		}
		
		commits = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: ShowLibrary.commitEvery)
				self?.commit()
			}
		}
		
		saves = Task { [weak self] in
			for await note in NotificationCenter.default.notifications(named: ModelContext.didSave) {
				self?.saved(Self.folders(in: note))
			}
		}
	}
	
	var active: Show {
		shows.first { $0.id == activeID } ?? Self.nothing
	}
	
	var standby: Standby {
		guard !isLoaded else { return .ready }
		guard isSettled, let console else { return .starting }
		guard !console.link.isConnected else { return .opening }
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
		
		let connected = console.link.isConnected
		defer { wasConnected = connected }
		
		guard connected else {
			sent = [:]
			deferred = []
			loading?.cancel()
			loading = nil
			guard !isDemo, isLoaded, dropping == nil else { return }
			
			dropping = Task {
				try? await Task.sleep(for: .seconds(2))
				guard !Task.isCancelled else { return }
				unload()
			}
			return
		}
		
		dropping?.cancel()
		dropping = nil
		
		if isDemo {
			isDemo = false
			unload()
		}
		
		guard !isLoaded || !wasConnected else { return }
		startLoading()
	}
	
	func startDemo() {
		guard !isDemo else { return }
		guard let url = Bundle.main.url(forResource: "Demo", withExtension: "json") else { return }
		guard let data = try? Data(contentsOf: url), let file = try? decoder.decode(ShowFile.self, from: data), file.isReadable else { return }
		
		isDemo = true
		let show = Show(name: file.name)
		shows = [show]
		activeID = show.id
		loadedID = show.id
		
		enqueue {
			await self.fill(with: file.show)
			self.isLoaded = true
		}
	}
	
	func stopDemo() {
		guard isDemo else { return }
		isDemo = false
		unload()
		guard console?.link.isConnected == true else { return }
		startLoading()
	}
	
	func settle(_ phase: ScenePhase) {
		guard phase != .active, isLoaded, !isDemo else { return }
		
		enqueue {
			await self.synchronise(Self.everything)
		}
	}
	
	func activate(_ show: Show) {
		guard show.id != activeID else { return }
		activeID = show.id
		
		switchTo(show) { list in
			list.active = show.id
		}
	}
	
	func create(name: String) {
		let show = Show(name: Self.unusedName(name, among: shows))
		shows.append(show)
		activeID = show.id
		
		switchTo(show) { list in
			list.shows.append(show)
			list.active = show.id
		}
	}
	
	func duplicate(_ show: Show) {
		enqueue {
			guard let endpoint = self.endpoint else { return }
			
			var found: ShowContents?
			if show.id == self.loadedID {
				found = self.contents()
			} else {
				found = await self.store.show(show.id, at: endpoint)
			}
			
			guard let copy = found else { return }
			await self.adopt(copy, named: show.name)
		}
	}
	
	func rename(_ show: Show, to name: String) {
		guard let index = shows.firstIndex(where: { $0.id == show.id }) else { return }
		shows[index].name = name
		
		enqueue {
			await self.commit { list in
				guard let found = list.shows.firstIndex(where: { $0.id == show.id }) else { return }
				list.shows[found].name = name
			}
		}
	}
	
	func delete(_ show: Show) {
		guard shows.count > 1 else { return }
		let wasActive = show.id == activeID
		shows.removeAll { $0.id == show.id }
		if wasActive, let next = shows.first { activeID = next.id }
		let started = epoch
		
		enqueue {
			await self.commit { list in
				list.shows.removeAll { $0.id == show.id }
				guard list.active == show.id else { return }
				list.active = list.shows.first?.id ?? ""
			}
			
			if let endpoint = self.endpoint {
				_ = await self.store.deleteShow(show.id, at: endpoint, client: self.client)
			}
			
			guard wasActive, let next = self.shows.first(where: { $0.id == self.activeID }) else { return }
			await self.open(next, since: started)
		}
	}
	
	func contents(_ folders: Set<NodeStore.Folder> = everything, only identifier: String? = nil) -> ShowContents {
		let context = container.mainContext
		var show = ShowContents()
		var fixtures: [Fixture] = []
		
		if !folders.isDisjoint(with: [.lights, .made]) { fixtures = (try? context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		if folders.contains(.lights) { show.lights = fixtures.map(\.entry) }
		if folders.contains(.groups) { show.groups = ((try? context.fetch(FetchDescriptor<FixtureGroup>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []).map(\.entry) }
		if folders.contains(.scenes) { show.scenes = ((try? context.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []).map(\.entry) }
		
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
		show.scenes.removeAll { $0.identifier != identifier }
		return show
	}
	
	func exportable() -> ShowFile {
		ShowFile(name: active.name, show: contents())
	}
	
	func adopt(contentsOf url: URL) {
		let isScoped = url.startAccessingSecurityScopedResource()
		defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
		guard let data = try? Data(contentsOf: url), let file = try? decoder.decode(ShowFile.self, from: data), file.isReadable else { return }
		
		enqueue {
			await self.adopt(file.show, named: file.name)
		}
	}
	
	static func unusedName(_ base: String, among shows: [Show]) -> String {
		let taken = Set(shows.map(\.name))
		guard taken.contains(base) else { return base }
		var index = 2
		
		while taken.contains("\(base) \(index)") {
			index += 1
		}
		
		return "\(base) \(index)"
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
	
	private func switchTo(_ show: Show, listing change: @escaping @MainActor (inout ShowList) -> Void) {
		let started = epoch
		
		enqueue {
			await self.synchronise(Self.everything)
			await self.commit(change)
			await self.open(show, since: started)
		}
	}
	
	private func startLoading() {
		guard loading == nil else { return }
		
		loading = Task {
			while !Task.isCancelled {
				if await enqueue({ await self.load() }).value { break }
				try? await Task.sleep(for: .seconds(2))
			}
			
			guard !Task.isCancelled else { return }
			loading = nil
		}
	}
	
	private func load() async -> Bool {
		guard let endpoint, console?.link.isConnected == true else { return false }
		let started = epoch
		
		switch await store.shows(at: endpoint) {
		case .unreachable:
			return false
		case .blank:
			let first = Show(name: "Show 1")
			
			guard await commit({ list in
				list.shows = [first]
				list.active = first.id
			}) else { return false }
			
			return await open(first, since: started, retrying: false)
		case let .list(list):
			if isLoaded, list.shows.contains(where: { $0.id == loadedID }) {
				await synchronise(Self.everything, direct: true)
			}
			
			guard let show = list.activeShow else { return false }
			shows = list.shows
			activeID = show.id
			return await open(show, since: started, retrying: false)
		}
	}
	
	@discardableResult private func open(_ show: Show, since started: Int, retrying: Bool = true) async -> Bool {
		guard let endpoint, let incoming = await store.show(show.id, at: endpoint), started == epoch else {
			if retrying {
				unload()
				startLoading()
			}
			return false
		}
		
		if !loadedID.isEmpty, loadedID != show.id {
			console?.closeShow()
		}
		
		loadedID = show.id
		await fill(with: incoming)
		guard started == epoch else { return false }
		activeID = show.id
		isLoaded = true
		changed(Self.everything)
		return true
	}
	
	private func adopt(_ contents: ShowContents, named name: String) async {
		guard let endpoint else { return }
		await synchronise(Self.everything)
		
		let show = Show(name: Self.unusedName(name, among: shows))
		shows.append(show)
		activeID = show.id
		
		for (key, data) in await Self.snapshot(of: contents) {
			guard let (folder, identifier) = Self.split(key) else { continue }
			_ = await store.put(data, folder: folder, id: identifier, in: show.id, at: endpoint, client: client)
		}
		
		await commit { list in
			list.shows.append(show)
			list.active = show.id
		}
		
		await open(show, since: epoch)
	}
	
	private func receive(_ notice: Wire.Notice) {
		guard !isDemo else { return }
		
		enqueue {
			await self.accept(notice)
		}
	}
	
	private func accept(_ notice: Wire.Notice) async {
		guard let endpoint, isLoaded, !isDemo else { return }
		
		guard let name = notice.folder, let identifier = notice.id, let show = notice.show else {
			guard case let .list(list) = await store.shows(at: endpoint) else { return }
			shows = list.shows
			guard let opening = list.activeShow, opening.id != loadedID else { return }
			activeID = opening.id
			let started = epoch
			await synchronise(Self.everything)
			await open(opening, since: started)
			return
		}
		
		guard show == loadedID, let folder = NodeStore.Folder(rawValue: name) else { return }
		let key = "\(name)/\(identifier)"
		
		if let landed = notice.landed {
			if landed, let data = sent[key] {
				baseline[key] = data.isEmpty ? nil : data
			}
			
			sent[key] = nil
			guard deferred.remove(key) != nil else { return }
			changed([folder])
			return
		}
		
		var data = notice.body
		if data == nil, !notice.isDelete {
			data = await store.object(folder, id: identifier, in: show, at: endpoint)
			guard data != nil, show == loadedID else { return }
		}
		
		let related: Set<NodeStore.Folder> = switch folder {
		case .groups: [.lights]
		case .lights: [.made]
		case .made, .scenes: []
		}
		let before = Self.encoded(contents(related), folders: related)
		
		if let data {
			var wrapped = Data("{\"\(name)\":[".utf8)
			wrapped.append(data)
			wrapped.append(Data("]}".utf8))
			guard let single = try? decoder.decode(ShowContents.self, from: wrapped) else { return }
			merge(single)
		} else {
			remove(folder, identifier: identifier)
		}
		
		let after = Self.encoded(contents(related), folders: related)
		baseline[key] = Self.encoded(contents([folder], only: identifier), folders: [folder])[key]
		
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
	
	private func saved(_ folders: Set<NodeStore.Folder>) {
		let context = container.mainContext
		canUndo = context.undoManager?.canUndo == true
		
		if let types, !folders.isDisjoint(with: [.lights, .made]) {
			types.setMade(((try? context.fetch(FetchDescriptor<StoredFixtureType>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []).map(\.definition))
			console?.applyPatch((try? context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [], library: types)
		}
		
		changed(folders)
	}
	
	private func merge(_ incoming: ShowContents) {
		let context = container.mainContext
		context.undoManager?.disableUndoRegistration()
		defer { context.undoManager?.enableUndoRegistration() }
		
		var groups = Dictionary(((try? context.fetch(FetchDescriptor<FixtureGroup>())) ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
		let fixtures = Dictionary(((try? context.fetch(FetchDescriptor<Fixture>())) ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
		let made = Dictionary(((try? context.fetch(FetchDescriptor<StoredFixtureType>())) ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
		let looks = Dictionary(((try? context.fetch(FetchDescriptor<Look>())) ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
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
			let look = looks[entry.identifier] ?? Look(name: entry.name, sortIndex: entry.sortIndex, levels: entry.levels)
			if look.modelContext == nil { context.insert(look) }
			look.take(entry)
		}
		
		try? context.save()
	}
	
	private func remove(_ folder: NodeStore.Folder, identifier: String) {
		let context = container.mainContext
		context.undoManager?.disableUndoRegistration()
		defer { context.undoManager?.enableUndoRegistration() }
		
		switch folder {
		case .lights: try? context.delete(model: Fixture.self, where: #Predicate { $0.identifier == identifier })
		case .groups: try? context.delete(model: FixtureGroup.self, where: #Predicate { $0.identifier == identifier })
		case .made: try? context.delete(model: StoredFixtureType.self, where: #Predicate { $0.identifier == identifier })
		case .scenes: try? context.delete(model: Look.self, where: #Predicate { $0.identifier == identifier })
		}
		
		try? context.save()
	}
	
	private func unload() {
		loading?.cancel()
		loading = nil
		guard isLoaded else { return }
		epoch += 1
		isLoaded = false
		shows = []
		activeID = ""
		loadedID = ""
		baseline = [:]
		sent = [:]
		deferred = []
		waiting = []
		clear()
		console?.closeShow()
	}
	
	private func fill(with incoming: ShowContents) async {
		clear()
		merge(incoming)
		sent = [:]
		deferred = []
		baseline = await Self.snapshot(of: incoming)
	}
	
	@discardableResult private func commit(_ change: (inout ShowList) -> Void) async -> Bool {
		guard let endpoint, !isDemo else { return false }
		
		var list = ShowList(active: "", shows: [])
		
		switch await store.shows(at: endpoint) {
		case let .list(latest): list = latest
		case .blank: break
		case .unreachable: return false
		}
		
		change(&list)
		shows = list.shows
		activeID = list.active
		return await store.save(list, at: endpoint, client: client)
	}
	
	private func changed(_ folders: Set<NodeStore.Folder>) {
		guard isLoaded, !isDemo, !folders.isEmpty else { return }
		waiting.formUnion(folders)
		guard pending == nil else { return }
		let delay = Self.coalesce - Date().timeIntervalSince(lastSync)
		
		pending = Task {
			if delay > 0 {
				try? await Task.sleep(for: .seconds(delay))
			}
			
			pending = nil
			
			enqueue {
				let touched = self.waiting
				self.waiting = []
				self.lastSync = Date()
				await self.synchronise(touched)
			}
		}
	}
	
	private func synchronise(_ folders: Set<NodeStore.Folder>, direct: Bool = false) async {
		guard let endpoint, isLoaded, !isDemo, !folders.isEmpty else { return }
		
		let showID = loadedID
		let current = await Self.snapshot(of: contents(folders), folders: folders)
		let isLive = !direct && console?.link.isConnected == true
		guard showID == loadedID else { return }
		
		var changes = current.filter { baseline[$0.key] != $0.value }
		
		for key in baseline.keys where current[key] == nil {
			guard let (folder, _) = Self.split(key), folders.contains(folder) else { continue }
			changes[key] = Data()
		}
		
		for (key, data) in changes {
			guard let (folder, identifier) = Self.split(key) else { continue }
			
			guard sent[key] == nil else {
				deferred.insert(key)
				continue
			}
			
			if isLive, data.count <= Self.frameLimit {
				sent[key] = data
				console?.send(document: Wire.document(show: showID, folder: folder.rawValue, id: identifier, body: data.isEmpty ? nil : data))
				continue
			}
			
			var isStored = false
			if data.isEmpty {
				isStored = await store.delete(folder, id: identifier, in: showID, at: endpoint, client: client)
			} else {
				isStored = await store.put(data, folder: folder, id: identifier, in: showID, at: endpoint, client: client)
			}
			
			guard showID == loadedID else { return }
			guard isStored else { continue }
			baseline[key] = data.isEmpty ? nil : data
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
				out["\(NodeStore.Folder.scenes.rawValue)/\(scene.identifier)"] = try? encoder.encode(scene)
			}
		}
		
		return out
	}
	
	nonisolated static func folders(in note: Notification) -> Set<NodeStore.Folder> {
		guard let info = note.userInfo else { return everything }
		
		var found: Set<NodeStore.Folder> = []
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
				default: break
				}
			}
		}
		
		return sawKey ? found : everything
	}
	
	nonisolated private static func split(_ key: String) -> (NodeStore.Folder, String)? {
		let parts = key.split(separator: "/", maxSplits: 1)
		guard parts.count == 2, let folder = NodeStore.Folder(rawValue: String(parts[0])) else { return nil }
		return (folder, String(parts[1]))
	}
	
	private func clear() {
		let context = container.mainContext
		try? context.delete(model: Fixture.self)
		try? context.delete(model: FixtureGroup.self)
		try? context.delete(model: StoredFixtureType.self)
		try? context.delete(model: Look.self)
		try? context.save()
		context.undoManager?.removeAllActions()
	}
	
	private static func store() -> ModelContainer {
		let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
		let container = try! ModelContainer(for: Fixture.self, FixtureGroup.self, StoredFixtureType.self, Look.self, configurations: configuration)
		container.mainContext.undoManager = UndoManager()
		container.mainContext.autosaveEnabled = true
		return container
	}
}
