import SwiftData
import SwiftUI

@Model
final class Look {
	var name: String = ""
	var sortIndex: Int = 0
	var levels: Data = Data()
	
	init(name: String, sortIndex: Int, levels: [String: [UInt8]]) {
		self.name = name
		self.sortIndex = sortIndex
		self.levels = (try? JSONEncoder().encode(levels)) ?? Data()
	}
	
	var fixtureLevels: [String: [UInt8]] {
		(try? JSONDecoder().decode([String: [UInt8]].self, from: levels)) ?? [:]
	}
	
	var fixtureCount: Int { fixtureLevels.count }
}
