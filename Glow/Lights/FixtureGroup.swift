import SwiftData
import SwiftUI

@Model
final class FixtureGroup {
	var identifier: String = Identifier.fresh()
	var name: String = ""
	var sortIndex: Double = 0
	var symbolOverride: String?
	var tintName: String?
	
	@Relationship(deleteRule: .nullify, inverse: \Fixture.groups)
	var fixtures: [Fixture]? = []
	
	init(name: String, sortIndex: Double) {
		identifier = Identifier.fresh()
		self.name = name
		self.sortIndex = sortIndex
	}
	
	var entry: ShowContents.Group {
		ShowContents.Group(identifier: identifier, name: name, sortIndex: sortIndex, symbol: symbolOverride, tint: tintName)
	}
	
	func take(_ entry: ShowContents.Group) {
		identifier = entry.identifier
		name = entry.name
		sortIndex = entry.sortIndex
		symbolOverride = entry.symbol
		tintName = entry.tint
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
