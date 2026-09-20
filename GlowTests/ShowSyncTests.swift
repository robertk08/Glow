import Foundation
import SwiftData
import Testing

@testable import Glow

private final class Box: @unchecked Sendable {
	var folders: Set<NodeStore.Folder>?
}

@MainActor
struct ShowSyncTests {
	private func show(lightNamed name: String) -> ShowContents {
		let light = ShowContents.Light(identifier: "par", typeID: "par", name: name, address: 1, sortIndex: 0)
		let group = ShowContents.Group(identifier: "front", name: "Front", sortIndex: 0)
		let scene = ShowContents.Scene(identifier: "look", name: "Look", sortIndex: 0, levels: ["par": Data([1, 2, 3])])
		return ShowContents(lights: [light], groups: [group], scenes: [scene])
	}
	
	@Test func everyObjectIsKeyedByItsFolderAndIdentifier() async {
		let keys = Set(await ShowLibrary.snapshot(of: show(lightNamed: "Par")).keys)
		
		#expect(keys == ["lights/par", "groups/front", "scenes/look"])
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
	
	@Test func aSceneStoresOneBlobOfBytesPerLight() throws {
		let scene = ShowContents.Scene(identifier: "look", name: "Look", sortIndex: 0, levels: ["par": Data([0, 128, 255])])
		let text = try #require(String(data: try JSONEncoder().encode(scene), encoding: .utf8))
		
		#expect(text.contains("\"par\":\"AID\\/\""))
		
		let decoded = try JSONDecoder().decode(ShowContents.Scene.self, from: try JSONEncoder().encode(scene))
		#expect(decoded.levels["par"] == Data([0, 128, 255]))
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
		
		for scene in file.show.scenes {
			#expect(scene.levels.count == file.show.lights.count)
			
			for light in file.show.lights {
				let type = try #require(library.type(light.typeID))
				#expect(scene.levels[light.identifier]?.count == type.channelCount)
			}
		}
	}
	
	@Test func aShowWithNoFoldersYetDecodesAsAnEmptyOne() throws {
		let empty = try JSONDecoder().decode(ShowContents.self, from: Data("{}".utf8))
		
		#expect(empty.lights.isEmpty)
		#expect(empty.groups.isEmpty)
		#expect(empty.made.isEmpty)
		#expect(empty.scenes.isEmpty)
	}
	
	@Test func aFolderTheAppDoesNotKnowYetIsIgnored() throws {
		let text = #"{"lights":[],"cues":[{"anything":1}]}"#
		let decoded = try JSONDecoder().decode(ShowContents.self, from: Data(text.utf8))
		
		#expect(decoded.lights.isEmpty)
	}
	
	@Test func savingASceneMarksOnlyTheScenesFolder() throws {
		let container = try ModelContainer(for: Fixture.self, FixtureGroup.self, StoredFixtureType.self, Look.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let context = container.mainContext
		let box = Box()
		
		let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { note in
			box.folders = ShowLibrary.folders(in: note)
		}
		defer { NotificationCenter.default.removeObserver(token) }
		
		context.insert(Look(name: "Look", sortIndex: 0, levels: [:]))
		try context.save()
		
		#expect(box.folders == [.scenes])
	}
	
	@Test func anExportFromAnotherFormatIsRefused() {
		var file = ShowFile(name: "Show", show: ShowContents())
		file.version = "2020-01-01"
		
		#expect(!file.isReadable)
	}
}
