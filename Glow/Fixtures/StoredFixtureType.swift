import SwiftData
import SwiftUI

@Model
final class StoredFixtureType {
	var identifier: String = ""
	var createdAt: Date = Date.now
	var definition: FixtureType = FixtureType.blank
	
	init(_ definition: FixtureType) {
		identifier = definition.id
		self.definition = definition
		createdAt = .now
	}
}
