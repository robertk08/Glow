import Foundation
import Testing

@testable import Glow

@MainActor
struct StorageTests {
	private static let filesystem = 0x5E0000
	private static let block = 4096
	private static let lights = 50
	private static let channels = 20
	
	private static func onDisk(_ data: Data) -> Int {
		max(1, (data.count + block - 1) / block) * block
	}
	
	private static func rig() -> ShowContents {
		var show = ShowContents()
		show.made = FixtureLibrary().builtIn
		
		for index in 0..<lights {
			show.lights.append(ShowContents.Light(identifier: Identifier.fresh(), typeID: "eight", name: "Light \(index)", address: index * channels + 1, sortIndex: Double(index)))
		}
		
		var levels: [String: Data] = [:]
		
		for light in show.lights {
			levels[light.identifier] = Data(repeating: 200, count: channels)
		}
		
		show.scenes = [ShowContents.Scene(identifier: Identifier.fresh(), name: "Look", sortIndex: 0, levels: levels)]
		return show
	}
	
	@Test func aSceneCostsLessThanSixtyBytesPerLight() async throws {
		let show = Self.rig()
		let files = await ShowLibrary.snapshot(of: show, folders: [.scenes])
		let scene = try #require(files.values.first)
		
		#expect(scene.count / Self.lights < 60)
	}
	
	@Test func aLightCostsLessThanOneHundredTwentyBytes() async throws {
		let show = Self.rig()
		let files = await ShowLibrary.snapshot(of: show, folders: [.lights])
		let light = try #require(files.values.max(by: { $0.count < $1.count }))
		
		#expect(light.count < 120)
	}
	
	@Test func theBundledDefinitionsFitInSixtyKilobytes() async {
		let show = Self.rig()
		let files = await ShowLibrary.snapshot(of: show, folders: [.made])
		let total = files.values.reduce(0) { $0 + $1.count }
		
		#expect(files.count == 4)
		#expect(total < 60_000)
	}
	
	@Test func aFiftyLightShowHoldsAtLeastAThousandScenes() async throws {
		let show = Self.rig()
		let files = await ShowLibrary.snapshot(of: show)
		let scene = try #require(files.first { $0.key.hasPrefix("scenes/") }?.value)
		
		var fixed = 0
		
		for (key, data) in files where !key.hasPrefix("scenes/") {
			fixed += Self.onDisk(data)
		}
		
		let room = Self.filesystem - fixed
		let each = Self.onDisk(scene)
		
		#expect(room / each >= 1000)
	}
	
	@Test func theWholeShowIsATinyShareOfTheFilesystem() async {
		let files = await ShowLibrary.snapshot(of: Self.rig())
		let total = files.values.reduce(0) { $0 + Self.onDisk($1) }
		
		#expect(total < Self.filesystem / 8)
	}
}
