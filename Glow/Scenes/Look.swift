import SwiftData
import SwiftUI

@Model
final class Look {
	var identifier: String = Identifier.fresh()
	var name: String = ""
	var sortIndex: Double = 0
	var levels: [String: Data] = [:]
	
	init(name: String, sortIndex: Double, levels: [String: Data]) {
		identifier = Identifier.fresh()
		self.name = name
		self.sortIndex = sortIndex
		self.levels = levels
	}
	
	var fixtureCount: Int { levels.count }
	
	var entry: ShowContents.Scene {
		ShowContents.Scene(identifier: identifier, name: name, sortIndex: sortIndex, levels: levels)
	}
	
	func take(_ entry: ShowContents.Scene) {
		identifier = entry.identifier
		name = entry.name
		sortIndex = entry.sortIndex
		levels = entry.levels
	}
}
