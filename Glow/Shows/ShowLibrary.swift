import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class ShowLibrary {
	private(set) var shows: [Show] = []
	private(set) var activeID = ""
	let container = ShowLibrary.store()
	private(set) var isLoaded = false
	private(set) var isDemo = false
	
	private let store = NodeStore()
	private let decoder = JSONDecoder()
	
	private var console: Console?
	private var types: FixtureLibrary?
	private var endpoint: NodeEndpoint?
	private var client: Int?
	private var loadedID = ""
	private var epoch = 0
	private var baseline: [String: Data] = [:]
	private var inFlight: [String: Data] = [:]
	private var erasing: Set<String> = []
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
	
	private static let nothing = Show(name: "")
	nonisolated private static let everything = Set(NodeStore.Folder.allCases)
	private static let frameLimit = 12000
	private static let coalesce: TimeInterval = 0.08
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
				let touched = Self.folders(in: note)
				self?.changed(touched)
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
			inFlight = [:]
			erasing = []
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
		let started = epoch
		
		enqueue {
			await self.synchronise(Self.everything)
			
			await self.commit { list in
				list.active = show.id
			}
			
			guard await self.open(show, since: started) else {
				self.reload()
				return
			}
		}
	}
	
	func create(name: String) {
		let show = Show(name: Self.unusedName(name, among: shows))
		shows.append(show)
		activeID = show.id
		let started = epoch
		
		enqueue {
			await self.synchronise(Self.everything)
			
			await self.commit { list in
				list.shows.append(show)
				list.active = show.id
			}
			
			guard await self.open(show, since: started) else {
				self.reload()
				return
			}
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
			
			guard await self.open(next, since: started) else {
				self.reload()
				return
			}
		}
	}
	
	func contents() -> ShowContents {
		contents(Self.everything)
	}
	
	func contents(_ folders: Set<NodeStore.Folder>, only identifier: String? = nil) -> ShowContents {
		let context = container.mainContext
		var fixtures: [Fixture] = []
		var groups: [FixtureGroup] = []
		var made: [StoredFixtureType] = []
		var looks: [Look] = []
		
		if !folders.isDisjoint(with: [.lights, .made]) { fixtures = (try? context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		if folders.contains(.groups) { groups = (try? context.fetch(FetchDescriptor<FixtureGroup>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		if folders.contains(.made) { made = (try? context.fetch(FetchDescriptor<StoredFixtureType>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [] }
		if folders.contains(.scenes) { looks = (try? context.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		
		var show = ShowContents()
		
		for group in groups where identifier == nil || group.identifier == identifier {
			show.groups.append(ShowContents.Group(identifier: group.identifier, name: group.name, sortIndex: group.sortIndex, symbol: group.symbolOverride, tint: group.tintName))
		}
		
		if folders.contains(.lights) {
			for fixture in fixtures where identifier == nil || fixture.identifier == identifier {
				let identifiers = fixture.belongsTo.map(\.identifier)
				show.lights.append(ShowContents.Light(identifier: fixture.identifier, typeID: fixture.typeID, name: fixture.name, address: fixture.address, sortIndex: fixture.sortIndex, symbol: fixture.symbolOverride, groups: identifiers, invertsPan: fixture.invertsPan, invertsTilt: fixture.invertsTilt))
			}
		}
		
		for stored in made {
			show.made.append(stored.definition)
		}
		
		if folders.contains(.made), let types {
			var carried = Set(show.made.map(\.id))
			
			for fixture in fixtures where !carried.contains(fixture.typeID) {
				guard let definition = types.type(fixture.typeID) else { continue }
				carried.insert(definition.id)
				show.made.append(definition)
			}
		}
		
		if let identifier {
			show.made.removeAll { $0.id != identifier }
		}
		
		for look in looks where identifier == nil || look.identifier == identifier {
			show.scenes.append(ShowContents.Scene(identifier: look.identifier, name: look.name, sortIndex: look.sortIndex, levels: look.levels))
		}
		
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
	
	private func reload() {
		unload()
		startLoading()
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
			
			return await open(first, since: started)
		case let .list(list):
			if isLoaded, list.shows.contains(where: { $0.id == loadedID }) {
				await synchronise(Self.everything, direct: true)
			}
			
			guard let show = list.activeShow else { return false }
			shows = list.shows
			activeID = show.id
			return await open(show, since: started)
		}
	}
	
	private func open(_ show: Show, since started: Int) async -> Bool {
		guard let endpoint, let incoming = await store.show(show.id, at: endpoint), started == epoch else { return false }
		
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
		let started = epoch
		await synchronise(Self.everything)
		
		let show = Show(name: Self.unusedName(name, among: shows))
		shows.append(show)
		activeID = show.id
		
		for (key, data) in await Self.snapshot(of: contents) {
			guard let folder = Self.folder(key), let identifier = Self.identifier(key) else { continue }
			_ = await store.put(data, folder: folder, id: identifier, in: show.id, at: endpoint, client: client)
		}
		
		await commit { list in
			list.shows.append(show)
			list.active = show.id
		}
		
		guard await open(show, since: started) else {
			reload()
			return
		}
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
			
			guard await open(opening, since: started) else {
				reload()
				return
			}
			return
		}
		
		guard show == loadedID, let folder = NodeStore.Folder(rawValue: name) else { return }
		let key = "\(name)/\(identifier)"
		
		if let landed = notice.landed {
			let sent = inFlight.removeValue(forKey: key)
			let erased = erasing.remove(key) != nil
			
			if landed, let sent {
				baseline[key] = sent
			} else if landed, erased {
				baseline.removeValue(forKey: key)
			}
			
			guard deferred.remove(key) != nil else { return }
			changed([folder])
			return
		}
		
		var data = notice.body
		if data == nil, !notice.isDelete {
			data = await store.object(folder, id: identifier, in: show, at: endpoint)
			guard data != nil, show == loadedID else { return }
		}
		
		let related = Self.dependents(of: folder)
		let before = Self.encoded(contents(related), folders: related)
		apply(folder, data: data, identifier: identifier)
		let after = Self.encoded(contents(related), folders: related)
		
		baseline[key] = Self.encoded(contents([folder], only: identifier), folders: [folder])[key]
		
		for (other, fresh) in after where before[other] != fresh {
			baseline[other] = fresh
		}
		
		for other in before.keys where after[other] == nil {
			baseline.removeValue(forKey: other)
		}
	}
	
	private func commit() {
		guard isLoaded else { return }
		let context = container.mainContext
		guard context.hasChanges else { return }
		try? context.save()
	}
	
	private func apply(_ folder: NodeStore.Folder, data: Data?, identifier: String) {
		let context = container.mainContext
		
		switch folder {
		case .lights:
			let found = try? context.fetch(FetchDescriptor<Fixture>(predicate: #Predicate { $0.identifier == identifier })).first
			guard let data, let entry = try? decoder.decode(ShowContents.Light.self, from: data), let address = DMXAddress(entry.address) else {
				if let found { context.delete(found) }
				break
			}
			
			let fixture = found ?? Fixture(typeID: entry.typeID, name: entry.name, address: address, sortIndex: entry.sortIndex)
			fixture.identifier = entry.identifier
			fixture.typeID = entry.typeID
			fixture.address = entry.address
			fixture.name = entry.name
			fixture.sortIndex = entry.sortIndex
			fixture.symbolOverride = entry.symbol
			fixture.invertsPan = entry.invertsPan
			fixture.invertsTilt = entry.invertsTilt
			if found == nil { context.insert(fixture) }
			
			for group in (try? context.fetch(FetchDescriptor<FixtureGroup>())) ?? [] {
				fixture.belong(to: group, entry.groups.contains(group.identifier))
			}
		case .groups:
			let found = try? context.fetch(FetchDescriptor<FixtureGroup>(predicate: #Predicate { $0.identifier == identifier })).first
			guard let data, let entry = try? decoder.decode(ShowContents.Group.self, from: data) else {
				if let found { context.delete(found) }
				break
			}
			
			let group = found ?? FixtureGroup(name: entry.name, sortIndex: entry.sortIndex)
			group.identifier = entry.identifier
			group.name = entry.name
			group.sortIndex = entry.sortIndex
			group.symbolOverride = entry.symbol
			group.tintName = entry.tint
			if found == nil { context.insert(group) }
		case .made:
			let found = try? context.fetch(FetchDescriptor<StoredFixtureType>(predicate: #Predicate { $0.identifier == identifier })).first
			guard let data, let entry = try? decoder.decode(FixtureType.self, from: data) else {
				if let found { context.delete(found) }
				break
			}
			guard !(types?.builtIn ?? []).contains(where: { $0.id == entry.id }) else { break }
			
			if let found {
				found.definition = entry
			} else {
				context.insert(StoredFixtureType(entry))
			}
		case .scenes:
			let found = try? context.fetch(FetchDescriptor<Look>(predicate: #Predicate { $0.identifier == identifier })).first
			guard let data, let entry = try? decoder.decode(ShowContents.Scene.self, from: data) else {
				if let found { context.delete(found) }
				break
			}
			
			let look = found ?? Look(name: entry.name, sortIndex: entry.sortIndex, levels: entry.levels)
			look.identifier = entry.identifier
			look.name = entry.name
			look.sortIndex = entry.sortIndex
			look.levels = entry.levels
			if found == nil { context.insert(look) }
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
		inFlight = [:]
		erasing = []
		deferred = []
		waiting = []
		clear()
		console?.closeShow()
	}
	
	private func fill(with incoming: ShowContents) async {
		clear()
		
		let context = container.mainContext
		var groups: [String: FixtureGroup] = [:]
		
		for entry in incoming.groups {
			let group = FixtureGroup(name: entry.name, sortIndex: entry.sortIndex)
			group.identifier = entry.identifier
			group.symbolOverride = entry.symbol
			group.tintName = entry.tint
			context.insert(group)
			groups[entry.identifier] = group
		}
		
		for entry in incoming.lights {
			guard let address = DMXAddress(entry.address) else { continue }
			let fixture = Fixture(typeID: entry.typeID, name: entry.name, address: address, sortIndex: entry.sortIndex)
			fixture.identifier = entry.identifier
			fixture.symbolOverride = entry.symbol
			fixture.invertsPan = entry.invertsPan
			fixture.invertsTilt = entry.invertsTilt
			context.insert(fixture)
			
			for identifier in entry.groups {
				guard let group = groups[identifier] else { continue }
				fixture.belong(to: group, true)
			}
		}
		
		let shipped = Set((types?.builtIn ?? []).map(\.id))
		
		for entry in incoming.made where !shipped.contains(entry.id) {
			context.insert(StoredFixtureType(entry))
		}
		
		for entry in incoming.scenes {
			let look = Look(name: entry.name, sortIndex: entry.sortIndex, levels: entry.levels)
			look.identifier = entry.identifier
			context.insert(look)
		}
		
		try? context.save()
		context.undoManager?.removeAllActions()
		inFlight = [:]
		erasing = []
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
		guard isLoaded, !isDemo else { return }
		waiting.formUnion(folders)
		guard pending == nil else { return }
		let delay = Self.coalesce - Date().timeIntervalSince(lastSync)
		
		pending = Task {
			if delay > 0 {
				try? await Task.sleep(for: .seconds(delay))
			}
			
			pending = nil
			
			enqueue {
				await self.flush()
			}
		}
	}
	
	private func flush() async {
		let touched = waiting
		waiting = []
		lastSync = Date()
		await synchronise(touched)
	}
	
	private func synchronise(_ folders: Set<NodeStore.Folder>, direct: Bool = false) async {
		guard let endpoint, isLoaded, !isDemo, !folders.isEmpty else { return }
		
		let showID = loadedID
		let current = await Self.snapshot(of: contents(folders), folders: folders)
		let isLive = !direct && console?.link.isConnected == true
		guard showID == loadedID else { return }
		
		for (key, data) in current where baseline[key] != data {
			guard let folder = Self.folder(key), let identifier = Self.identifier(key) else { continue }
			
			guard inFlight[key] == nil, !erasing.contains(key) else {
				deferred.insert(key)
				continue
			}
			
			if isLive, data.count <= Self.frameLimit {
				inFlight[key] = data
				console?.send(document: Wire.document(show: showID, folder: folder.rawValue, id: identifier, body: data))
				continue
			}
			
			guard await store.put(data, folder: folder, id: identifier, in: showID, at: endpoint, client: client) else { continue }
			guard showID == loadedID else { return }
			baseline[key] = data
		}
		
		for key in baseline.keys where current[key] == nil {
			guard let folder = Self.folder(key), folders.contains(folder), let identifier = Self.identifier(key) else { continue }
			
			guard inFlight[key] == nil, !erasing.contains(key) else {
				deferred.insert(key)
				continue
			}
			
			if isLive {
				erasing.insert(key)
				console?.send(document: Wire.document(show: showID, folder: folder.rawValue, id: identifier, body: nil))
				continue
			}
			
			guard await store.delete(folder, id: identifier, in: showID, at: endpoint, client: client) else { continue }
			guard showID == loadedID else { return }
			baseline.removeValue(forKey: key)
		}
	}
	
	@concurrent nonisolated static func snapshot(of contents: ShowContents, folders: Set<NodeStore.Folder> = Set(NodeStore.Folder.allCases)) async -> [String: Data] {
		encoded(contents, folders: folders)
	}
	
	nonisolated static func encoded(_ contents: ShowContents, folders: Set<NodeStore.Folder>) -> [String: Data] {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		encoder.dateEncodingStrategy = .iso8601
		var out: [String: Data] = [:]
		
		if folders.contains(.lights) {
			for light in contents.lights {
				guard let data = try? encoder.encode(light) else { continue }
				out["\(NodeStore.Folder.lights.rawValue)/\(light.identifier)"] = data
			}
		}
		
		if folders.contains(.groups) {
			for group in contents.groups {
				guard let data = try? encoder.encode(group) else { continue }
				out["\(NodeStore.Folder.groups.rawValue)/\(group.identifier)"] = data
			}
		}
		
		if folders.contains(.made) {
			for made in contents.made {
				guard let data = try? encoder.encode(made) else { continue }
				out["\(NodeStore.Folder.made.rawValue)/\(made.id)"] = data
			}
		}
		
		if folders.contains(.scenes) {
			for scene in contents.scenes {
				guard let data = try? encoder.encode(scene) else { continue }
				out["\(NodeStore.Folder.scenes.rawValue)/\(scene.identifier)"] = data
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
				found.formUnion(Self.folders(entity: id.entityName))
			}
		}
		
		return sawKey ? found : everything
	}
	
	nonisolated private static func folders(entity: String) -> Set<NodeStore.Folder> {
		switch entity {
		case "Fixture": [.lights, .made]
		case "FixtureGroup": [.groups]
		case "StoredFixtureType": [.made]
		case "Look": [.scenes]
		default: []
		}
	}
	
	nonisolated private static func dependents(of folder: NodeStore.Folder) -> Set<NodeStore.Folder> {
		switch folder {
		case .groups: [.lights]
		case .lights: [.made]
		case .made, .scenes: []
		}
	}
	
	private static func folder(_ key: String) -> NodeStore.Folder? {
		guard let slash = key.firstIndex(of: "/") else { return nil }
		return NodeStore.Folder(rawValue: String(key[key.startIndex..<slash]))
	}
	
	private static func identifier(_ key: String) -> String? {
		guard let slash = key.firstIndex(of: "/") else { return nil }
		return String(key[key.index(after: slash)...])
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
