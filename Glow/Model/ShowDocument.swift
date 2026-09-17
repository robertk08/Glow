import SwiftUI
import UniformTypeIdentifiers

struct ShowDocument: FileDocument {
	static let readableContentTypes = [UTType.json]
	
	var show: ShowFile
	
	init(show: ShowFile) {
		self.show = show
	}
	
	init(configuration: ReadConfiguration) throws {
		guard let data = configuration.file.regularFileContents else {
			throw CocoaError(.fileReadCorruptFile)
		}
		show = try JSONDecoder().decode(ShowFile.self, from: data)
	}
	
	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return FileWrapper(regularFileWithContents: try encoder.encode(show))
	}
}
