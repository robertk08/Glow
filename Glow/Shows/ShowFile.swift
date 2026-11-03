import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated struct ShowFile: Codable, Sendable, Transferable {
	static let format = "glow.show"
	static let current = "2026-09-27"
	
	var format = ShowFile.format
	var version = ShowFile.current
	var exportedAt = Date.now
	var name: String
	var show: ShowContents
	
	var isReadable: Bool {
		format == ShowFile.format && version == ShowFile.current
	}
	
	static var transferRepresentation: some TransferRepresentation {
		DataRepresentation(exportedContentType: .json) { file in
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			encoder.dateEncodingStrategy = .iso8601
			return try encoder.encode(file)
		}
		.suggestedFileName { $0.name }
	}
	
	init(name: String, show: ShowContents) {
		self.name = name
		self.show = show
	}
}
