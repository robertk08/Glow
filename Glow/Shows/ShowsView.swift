import SwiftUI
import UniformTypeIdentifiers

struct ShowsView: View {
	@Environment(Console.self) private var console
	@Environment(ShowLibrary.self) private var shows
	
	@State private var isNaming = false
	@State private var newName = ""
	@State private var renaming: Show?
	@State private var renamed = ""
	@State private var deleting: Show?
	@State private var exporting: ShowDocument?
	@State private var isImporting = false
	
	var body: some View {
		List {
			Section {
				ForEach(shows.shows) { show in
					Button {
						console.closeShow()
						shows.activate(show)
					} label: {
						LabeledContent {
							Image(systemName: "checkmark")
								.foregroundStyle(.tint)
								.opacity(show.id == shows.activeID ? 1 : 0)
						} label: {
							Label(show.name, systemImage: "rectangle.stack")
						}
						.contentShape(.rect)
					}
					.buttonStyle(.plain)
					.contextMenu {
						Button("Rename", systemImage: "pencil") {
							renaming = show
							renamed = show.name
						}
						
						Button("Duplicate", systemImage: "plus.square.on.square") {
							console.closeShow()
							shows.duplicate(show)
						}
						
						if let url = shows.shareable(show) {
							ShareLink(item: url) {
								Label("Share", systemImage: "square.and.arrow.up")
							}
						}
						
						Button("Save to Files", systemImage: "folder") {
							exporting = ShowDocument(show: shows.contents(of: show))
						}
						
						Button("Delete", systemImage: "trash", role: .destructive) {
							deleting = show
						}
						.disabled(shows.shows.count < 2)
					}
					.swipeActions(edge: .trailing, allowsFullSwipe: false) {
						if shows.shows.count > 1 {
							Button("Delete", systemImage: "trash", role: .destructive) {
								deleting = show
							}
						}
					}
				}
			}
			
			Section {
				Button("Import Show", systemImage: "square.and.arrow.down") {
					isImporting = true
				}
				
				Button("New Show", systemImage: "plus") {
					newName = ""
					isNaming = true
				}
			}
		}
		.confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding { deleting != nil } set: { _ in deleting = nil }, titleVisibility: .visible, presenting: deleting) { show in
			Button("Delete Show", role: .destructive) {
				console.closeShow()
				shows.delete(show)
			}
		} message: { _ in
			Text("Its patch, groups, built fixtures and scenes go with it, and there is no undo.")
		}
		.sensoryFeedback(.selection, trigger: shows.activeID)
		.navigationTitle("Shows")
		.navigationBarTitleDisplayMode(.inline)
		.fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
			guard let url = try? result.get() else { return }
			console.closeShow()
			shows.adopt(contentsOf: url)
		}
		.fileExporter(isPresented: Binding { exporting != nil } set: { _ in exporting = nil }, document: exporting, contentType: .json, defaultFilename: exporting?.show.name) { _ in }
		.sheet(isPresented: $isNaming) {
			NameSheet(title: "New Show", prompt: "Show", name: $newName) { name in
				console.closeShow()
				shows.create(name: name)
			}
		}
		.sheet(item: $renaming) { show in
			NameSheet(title: "Rename Show", prompt: "Show", name: $renamed) { name in
				shows.rename(show, to: name)
			}
		}
	}
}
