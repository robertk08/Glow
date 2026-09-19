import SwiftData
import SwiftUI

@Model
final class FixtureGroup {
	var name: String = ""
	var sortIndex: Int = 0
	var symbolOverride: String?
	var tintName: String?
	
	@Relationship(deleteRule: .nullify, inverse: \Fixture.group)
	var fixtures: [Fixture]? = []
	
	init(name: String, sortIndex: Int) {
		self.name = name
		self.sortIndex = sortIndex
	}
	
	var members: [Fixture] {
		(fixtures ?? []).sorted { $0.address < $1.address }
	}
	
	var tint: FixtureTint {
		get { tintName.flatMap(FixtureTint.init(rawValue:)) ?? .none }
		set { tintName = newValue == .none ? nil : newValue.rawValue }
	}
	
	var symbol: String {
		symbolOverride ?? "square.stack.3d.up"
	}
}
