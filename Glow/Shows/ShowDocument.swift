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
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		show = try decoder.decode(ShowFile.self, from: data)
	}
	
	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: try show.exported)
	}
}
