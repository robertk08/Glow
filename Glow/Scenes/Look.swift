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
}
