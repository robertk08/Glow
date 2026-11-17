import Foundation

nonisolated struct ShowList: Codable, Sendable, Equatable {
	var active: String
	var shows: [Show]
	
	var activeShow: Show? {
		shows.first { $0.id == active } ?? shows.first
	}
	
	mutating func apply(_ command: Wire.Command) {
		switch command {
		case let .addShow(show):
			shows.append(show)
			active = show.id
		case let .renameShow(show):
			guard let index = shows.firstIndex(where: { $0.id == show.id }) else { return }
			shows[index].name = show.name
		case let .sendAllChannels(show):
			guard let index = shows.firstIndex(where: { $0.id == show.id }) else { return }
			shows[index].sendsAllChannels = show.sendsAllChannels
		case let .removeShow(identifier):
			guard shows.count > 1 else { return }
			shows.removeAll { $0.id == identifier }
			if active == identifier { active = shows.first?.id ?? "" }
		case let .openShow(identifier):
			guard shows.contains(where: { $0.id == identifier }) else { return }
			active = identifier
		default:
			break
		}
	}
}
