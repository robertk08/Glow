import SwiftData
import SwiftUI

@Model
final class StoredFixtureType {
	var identifier: String = ""
	var createdAt: Date = Date.now
	private var encoded: Data = Data()
	
	init(_ definition: FixtureType) {
		identifier = definition.id
		createdAt = .now
		self.definition = definition
	}
	
	var definition: FixtureType {
		get { (try? JSONDecoder().decode(FixtureType.self, from: encoded)) ?? .blank }
		set { encoded = (try? JSONEncoder().encode(newValue)) ?? Data() }
	}
}
