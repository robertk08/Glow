import Foundation
import SwiftData
import Testing

@testable import Glow

private final class Box: @unchecked Sendable {
	var folders: Set<NodeStore.Folder>?
}

@MainActor
struct ShowSyncTests {
	private func until(_ condition: () -> Bool) async throws {
		for _ in 0..<300 {
			if condition() { return }
			try await Task.sleep(for: .milliseconds(10))
		}
		
		Issue.record("timed out")
	}
	
	private func show(lightNamed name: String) -> ShowContents {
		let light = ShowContents.Light(identifier: "par", typeID: "par", name: name, address: 1, sortIndex: 0)
		let group = ShowContents.Group(identifier: "front", name: "Front", sortIndex: 0)
		let scene = ShowContents.Scene(identifier: "look", name: "Look", sortIndex: 0)
		var levels = Levels()
		levels.set(255, slot: 1, of: "par")
		let cue = ShowContents.Cue(identifier: "cue", scene: "look", sortIndex: 1, levels: levels.data)
		return ShowContents(lights: [light], groups: [group], scenes: [scene], cues: [cue])
	}
	
	@Test func everyObjectIsKeyedByItsFolderAndIdentifier() async {
		let keys = Set(await ShowLibrary.snapshot(of: show(lightNamed: "Par")).keys)
		
		#expect(keys == ["lights/par", "groups/front", "scenes/look", "cues/cue"])
	}
	
	@Test func renamingOneLightTouchesOnlyThatLightsKey() async {
		let before = await ShowLibrary.snapshot(of: show(lightNamed: "Par"))
		let after = await ShowLibrary.snapshot(of: show(lightNamed: "Par 2"))
		let changed = after.filter { before[$0.key] != $0.value }
		
		#expect(changed.keys.sorted() == ["lights/par"])
		#expect(before.keys.sorted() == after.keys.sorted())
	}
	
	@Test func aDeletedObjectLeavesItsKeyBehindInTheBaseline() async {
		let before = await ShowLibrary.snapshot(of: show(lightNamed: "Par"))
		var trimmed = show(lightNamed: "Par")
		trimmed.scenes = []
		let after = await ShowLibrary.snapshot(of: trimmed)
		
		#expect(before.keys.filter { after[$0] == nil } == ["scenes/look"])
	}
	
	@Test func aFreshIdentifierIsShortAndPathSafe() {
		var seen: Set<String> = []
		
		for _ in 0..<1000 {
			let identifier = Identifier.fresh()
			#expect(identifier.count == 16)
			#expect(identifier.allSatisfy { $0.isHexDigit && !$0.isUppercase })
			seen.insert(identifier)
		}
		
		#expect(seen.count == 1000)
	}
	
	@Test func everyFolderNameIsSafeAsAPathOnTheController() {
		for folder in NodeStore.Folder.allCases {
			#expect(!folder.rawValue.isEmpty)
			#expect(folder.rawValue.count < 40)
			#expect(folder.rawValue.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
		}
	}
	
	@Test func aSceneAndACueReadBackAsWritten() throws {
		var levels = Levels()
		levels.set(255, slot: 1, of: "0123456789abcdef")
		levels.set(7, slot: 14, of: "0123456789abcdef")
		levels.set(128, slot: 3, of: "par")
		let scene = ShowContents.Scene(identifier: "look", name: "Évening", sortIndex: 2.5, symbol: "sun.max", tint: "orange", tap: .flash, buttons: [.back, .update])
		let cue = ShowContents.Cue(identifier: "cue", scene: "0123456789abcdef", sortIndex: 1.5, label: "The sun comes up over the hill", fade: 3.5, delay: 1, follow: 0, levels: levels.data)
		let held = ShowContents.Cue(identifier: "held", scene: "look", sortIndex: 2, follow: nil)
		
		let readScene = try #require(ShowContents.Scene(identifier: "look", body: scene.body))
		let readCue = try #require(ShowContents.Cue(identifier: "cue", body: cue.body))
		
		#expect(readScene.name == "Évening")
		#expect(readScene.sortIndex == 2.5)
		#expect(readScene.symbol == "sun.max")
		#expect(readScene.tint == "orange")
		#expect(readScene.tap == .flash)
		#expect(readScene.buttons == [.back, .update])
		#expect(readCue.scene == "0123456789abcdef")
		#expect(readCue.sortIndex == 1.5)
		#expect(readCue.label == "The sun comes up over the hill")
		#expect(readCue.fade == 3.5)
		#expect(readCue.delay == 1)
		#expect(readCue.follow == 0)
		#expect(try #require(ShowContents.Cue(identifier: "held", body: held.body)).follow == nil)
		#expect(Levels(readCue.levels) == levels)
	}
	
	@Test func aCueHoldsOnlyTheChannelsItStores() {
		var levels = Levels()
		levels.set(255, slot: 6, of: "0123456789abcdef")
		
		#expect(levels.data.count == 11)
		#expect(Levels(levels.data)?.lights["0123456789abcdef"] == [6: 255])
	}
	
	@Test func aLargeCueIsKeptSqueezed() throws {
		var levels = Levels()
		
		for _ in 0..<40 {
			let light = Identifier.fresh()
			
			for slot in 1...16 {
				levels.set(UInt8(slot * 8), slot: slot, of: light)
			}
		}
		
		let cue = ShowContents.Cue(identifier: "cue", scene: "look", sortIndex: 1, levels: levels.data)
		
		#expect(cue.body.first == 6)
		#expect(cue.body.count < levels.data.count * 2 / 3)
		#expect(try #require(ShowContents.Cue(identifier: "cue", body: cue.body)).levels == levels.data)
	}
	
	@Test func levelsMergeWithTheNewerValuesWinning() {
		var older = Levels()
		older.set(10, slot: 1, of: "a")
		older.set(20, slot: 2, of: "a")
		var newer = Levels()
		newer.set(99, slot: 2, of: "a")
		newer.set(5, slot: 1, of: "b")
		let merged = older.merging(newer)
		
		#expect(merged.lights["a"] == [1: 10, 2: 99])
		#expect(merged.lights["b"] == [1: 5])
		#expect(merged.removing("a").lights.keys.sorted() == ["b"])
	}
	
	@Test func aBrokenBodyIsNeverReadAsACue() {
		#expect(ShowContents.Cue(identifier: "cue", body: Data(#"{"identifier":"look","name":"Look","levels":{}}"#.utf8)) == nil)
		#expect(ShowContents.Scene(identifier: "look", body: Data(#"{"identifier":"look","name":"Look","sortIndex":0}"#.utf8)) == nil)
		#expect(ShowContents.Cue(identifier: "cue", body: Data([5, 0])) == nil)
		#expect(ShowContents.Cue(identifier: "cue", body: Data()) == nil)
	}
	
	@Test func theDemoShowPatchesAgainstTheBundledFixtures() throws {
		let url = try #require(Bundle.main.url(forResource: "Demo", withExtension: "json"))
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let file = try decoder.decode(ShowFile.self, from: try Data(contentsOf: url))
		let library = FixtureLibrary()
		
		#expect(file.isReadable)
		#expect(!file.show.lights.isEmpty)
		#expect(!file.show.scenes.isEmpty)
		#expect(file.show.cues.contains { !$0.label.isEmpty })
		
		var used: Set<Int> = []
		
		for light in file.show.lights {
			let type = try #require(library.type(light.typeID))
			let span = light.address...(light.address + type.channelCount - 1)
			#expect(span.upperBound <= 512)
			#expect(used.isDisjoint(with: span))
			used.formUnion(span)
			
			for identifier in light.groups {
				#expect(file.show.groups.contains { $0.identifier == identifier })
			}
		}
		
		for cue in file.show.cues {
			let levels = try #require(Levels(cue.levels))
			#expect(!levels.isEmpty)
			#expect(file.show.scenes.contains { $0.identifier == cue.scene })
			
			for (identifier, slots) in levels.lights {
				let light = try #require(file.show.lights.first { $0.identifier == identifier })
				let type = try #require(library.type(light.typeID))
				#expect(slots.keys.allSatisfy { $0 <= type.channelCount })
			}
		}
	}
	
	@Test func aShowWithNoFoldersYetDecodesAsAnEmptyOne() throws {
		let empty = try JSONDecoder().decode(ShowContents.self, from: Data("{}".utf8))
		
		#expect(empty.lights.isEmpty)
		#expect(empty.groups.isEmpty)
		#expect(empty.made.isEmpty)
		#expect(empty.scenes.isEmpty)
		#expect(empty.cues.isEmpty)
	}
	
	@Test func aFolderTheAppDoesNotKnowYetIsIgnored() throws {
		let text = #"{"lights":[],"effects":[{"anything":1}]}"#
		let decoded = try JSONDecoder().decode(ShowContents.self, from: Data(text.utf8))
		
		#expect(decoded.lights.isEmpty)
	}
	
	@Test func savingASceneMarksOnlyTheScenesFolder() throws {
		let container = try ModelContainer(for: Fixture.self, FixtureGroup.self, StoredFixtureType.self, Look.self, Cue.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let context = container.mainContext
		let box = Box()
		
		let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { note in
			box.folders = ShowLibrary.folders(in: note)
		}
		defer { NotificationCenter.default.removeObserver(token) }
		
		context.insert(Look(name: "Look", sortIndex: 0))
		try context.save()
		
		#expect(box.folders == [.scenes])
		
		context.insert(Cue(lookID: "look", sortIndex: 1, fade: 0, levels: Levels()))
		try context.save()
		
		#expect(box.folders == [.cues])
	}
	
	@Test func anExportFromAnotherFormatIsRefused() {
		var file = ShowFile(name: "Show", show: ShowContents())
		file.version = "2020-01-01"
		
		#expect(!file.isReadable)
	}
	
	@Test func savingALightAlsoSyncsTheDefinitionsItCarries() throws {
		let container = try ModelContainer(for: Fixture.self, FixtureGroup.self, StoredFixtureType.self, Look.self, Cue.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let context = container.mainContext
		let box = Box()
		
		let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { note in
			box.folders = ShowLibrary.folders(in: note)
		}
		defer { NotificationCenter.default.removeObserver(token) }
		
		context.insert(Fixture(typeID: "par", name: "Par", address: DMXAddress(1)!, sortIndex: 0))
		try context.save()
		
		#expect(box.folders == [.lights, .made])
	}
	
	@Test func aWriteTheControllerCouldNotStoreSaysWhichObject() throws {
		let reply = try #require(Wire.event(.string(#"{"t":"unwritten","show":"s","folder":"scenes","id":"look"}"#)))
		
		guard case let .notice(.landed(place, isWritten)) = reply else {
			Issue.record("expected a landed notice")
			return
		}
		
		#expect(!isWritten)
		#expect(place == Wire.Place(show: "s", folder: "scenes", id: "look"))
	}
	
	@Test func theDemoSwitchesBetweenItsOwnShowsAndKeepsTheirEdits() async throws {
		let library = ShowLibrary()
		library.startDemo()
		try await until { library.isLoaded }
		
		let demo = library.activeID
		let fixture = try #require(try library.container.mainContext.fetch(FetchDescriptor<Fixture>()).first)
		fixture.name = "Kept"
		try library.container.mainContext.save()
		
		library.create(name: "Rehearsal")
		try await until { library.activeID != demo && library.contents().lights.isEmpty }
		#expect(library.shows.count == 2)
		
		library.duplicate(library.shows[0])
		try await until { library.shows.count == 3 && library.contents().lights.contains { $0.name == "Kept" } }
		
		library.activate(library.shows[0])
		try await until { library.activeID == demo && library.contents().lights.contains { $0.name == "Kept" } }
		
		library.stopDemo()
		#expect(!library.isLoaded)
		#expect(library.shows.isEmpty)
	}
	
	@Test func theControllersListArrivesWholeWithItsActiveShow() throws {
		let reply = try #require(Wire.event(.string(#"{"t":"shows","active":"b","shows":[{"id":"a","name":"A"},{"id":"b","name":"B"}]}"#)))
		
		guard case let .notice(.shows(list)) = reply else {
			Issue.record("expected the show list")
			return
		}
		
		#expect(list.shows.map(\.name) == ["A", "B"])
		#expect(list.activeShow?.id == "b")
	}
	
	@Test func reopeningAShowKeepsTheObjectsAnOpenScreenHolds() async throws {
		let library = ShowLibrary()
		library.startDemo()
		try await until { library.isLoaded }
		
		let demo = library.activeID
		let fixture = try #require(try library.container.mainContext.fetch(FetchDescriptor<Fixture>()).first)
		fixture.name = "Edited"
		try library.container.mainContext.save()
		try await until { library.canUndo }
		
		library.duplicate(library.active)
		try await until { library.activeID != demo && !library.canUndo }
		
		#expect(!fixture.isDeleted)
		#expect(fixture.modelContext != nil)
		#expect(fixture.name == "Edited")
	}
	
	@Test func aRefusedShowCommandSaysWhy() throws {
		let reply = try #require(Wire.event(.string(#"{"t":"refused","reason":"limit"}"#)))
		
		guard case .notice(.refused(.limit)) = reply else {
			Issue.record("expected a refusal")
			return
		}
		
		#expect(Wire.event(.string(#"{"t":"refused","reason":"tired"}"#)) == nil)
	}
	
	@Test func aPongCarriesTheControllersMemoryAndStorage() throws {
		let reply = try #require(Wire.event(.string(#"{"t":"pong","seq":4,"ram":120000,"ramTotal":320000,"store":8192,"storeTotal":6225920}"#)))
		
		guard case let .pong(seq, usage) = reply else {
			Issue.record("expected a pong")
			return
		}
		
		#expect(seq == 4)
		#expect(usage == Wire.Usage(memory: 120000, memoryTotal: 320000, storage: 8192, storageTotal: 6225920))
	}
	
	@Test func aShowCommandNamesTheShowItActsOn() throws {
		var show = Show(name: "Gala")
		show.id = "gala"
		
		guard case let .string(text) = Wire.Command.addShow(show).message else {
			Issue.record("expected text")
			return
		}
		
		let fields = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String])
		#expect(fields == ["t": "show.add", "id": "gala", "name": "Gala"])
	}
	
	@Test func aShowNameFitsTheControllersLimitWithoutSplittingACharacter() {
		let name = Show(name: String(repeating: "é", count: 40)).name
		
		#expect(name.utf8.count <= 64)
		#expect(name == String(repeating: "é", count: 32))
		#expect(Show(name: "Gala").name == "Gala")
	}
	
	@Test func theListKeepsOneShowAndMovesTheActiveOneOnDelete() {
		let first = Show(name: "One")
		let second = Show(name: "Two")
		var list = ShowList(active: first.id, shows: [first])
		
		list.apply(.removeShow(first.id))
		#expect(list.shows == [first])
		
		list.apply(.addShow(second))
		#expect(list.active == second.id)
		
		list.apply(.openShow("missing"))
		#expect(list.active == second.id)
		
		list.apply(.removeShow(second.id))
		#expect(list.shows == [first])
		#expect(list.active == first.id)
	}
	
	@Test func aJoiningDeviceLearnsTheMasterAndBlackout() throws {
		let reply = try #require(Wire.event(.string(#"{"t":"status","src":true,"master":0.5,"blackout":true}"#)))
		
		guard case let .status(info) = reply else {
			Issue.record("expected a status")
			return
		}
		
		#expect(info.hasSource)
		#expect(info.master == 0.5)
		#expect(info.blackout)
	}
	
	@Test func aMadeIdentifierFitsTheControllersNames() {
		let library = FixtureLibrary(builtIn: [])
		let identifier = library.unusedIdentifier("An Extremely Long Fixture Model Name From A Manufacturer Who Loves Words")
		
		#expect(identifier.count < 40)
		#expect(identifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
		#expect(!identifier.hasSuffix("-"))
	}
	
	@Test func aDocumentFrameReadsBackAsWritten() throws {
		let body = Data(#"{"name":"Par"}"#.utf8)
		
		guard case let .notice(put) = try #require(Wire.event(.data(Wire.document(show: "show", folder: "lights", id: "par", body: body)))) else {
			Issue.record("expected a notice")
			return
		}
		
		guard case let .notice(erased) = try #require(Wire.event(.data(Wire.document(show: "show", folder: "lights", id: "par", body: nil)))) else {
			Issue.record("expected a notice")
			return
		}
		
		#expect(put == .stored(Wire.Place(show: "show", folder: "lights", id: "par"), body))
		#expect(erased == .erased(Wire.Place(show: "show", folder: "lights", id: "par")))
		#expect(Wire.event(.data(Wire.document(show: "show", folder: "lights", id: "par", body: body).dropLast())) == nil)
	}
	
	@Test func aShowFileKeepsTheNewestRecordOfEachObjectAndSkipsBrokenOnes() {
		let records: [(folder: String, id: String, body: String?)] = [
			("lights", "par", #"{"identifier":"par","typeID":"par","name":"Old","address":1}"#),
			("lights", "par", #"{"identifier":"par","typeID":"par","name":"New","address":1}"#),
			("lights", "wash", #"{"name":"Broken"}"#),
			("scenes", "look", #"{"identifier":"look","name":"Look"}"#),
			("scenes", "look", nil),
		]
		var log = Data()
		
		for record in records {
			let body = Data((record.body ?? "").utf8)
			log.append(contentsOf: [record.body == nil ? 1 : 0, UInt8(record.folder.utf8.count), UInt8(record.id.utf8.count), UInt8(body.count & 0xFF), UInt8(body.count >> 8)])
			log.append(Data(record.folder.utf8) + Data(record.id.utf8) + body)
		}
		
		log.append(contentsOf: [0, 6, 4, 200])
		let show = ShowContents(objects: Wire.objects(in: log))
		
		#expect(show.lights.map(\.name) == ["New"])
		#expect(show.scenes.isEmpty)
		#expect(show.unreadable == ["lights/wash"])
	}
	
	@Test func aSceneStoredBeforeCuesIsUnreadableSoItsShowErasesIt() {
		let old = Data(#"{"identifier":"look","name":"Look","sortIndex":0,"levels":{"par":"AID/"}}"#.utf8)
		let show = ShowContents(objects: [("scenes", "look", old), ("elsewhere", "thing", old)])
		
		#expect(show.scenes.isEmpty)
		#expect(show.unreadable == ["scenes/look"])
	}
	
	@Test func aSourceFrameReadsBackAsWritten() throws {
		guard case let .frame(start, values) = try #require(Wire.event(.data(Wire.frame(Wire.sourceOpcode, start: DMXAddress(510)!, values: [1, 2, 3])))) else {
			Issue.record("expected a frame")
			return
		}
		
		#expect(start.value == 510)
		#expect(values == [1, 2, 3])
		#expect(Wire.event(.data(Wire.frame(Wire.outputOpcode, start: DMXAddress(1)!, values: [1]))) == nil)
	}
}

