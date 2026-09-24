import SwiftUI
import UniformTypeIdentifiers

struct ShowsView: View {
	@Environment(ShowLibrary.self) private var shows
	
	@State private var isNaming = false
	@State private var newName = ""
	@State private var renaming: Show?
	@State private var renamed = ""
	@State private var deleting: Show?
	@State private var exporting: ShowFile?
	@State private var isImporting = false
	@State private var isRefused = false
	
	var body: some View {
		List {
			Section {
				ForEach(shows.shows) { show in
					Button {
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
							renamed = show.name
							renaming = show
						}
						
						Button("Duplicate", systemImage: "plus.square.on.square") {
							shows.duplicate(show)
						}
						
						if show.id == shows.activeID {
							ShareLink(item: shows.exportable(), preview: SharePreview(show.name)) {
								Label("Share", systemImage: "square.and.arrow.up")
							}
							
							Button("Save to Files", systemImage: "folder") {
								exporting = shows.exportable()
							}
						}
					}
					.swipeActions {
						if shows.shows.count > 1 {
							Button("Delete", systemImage: "trash") {
								deleting = show
							}
							.tint(.red)
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
		.sensoryFeedback(.selection, trigger: shows.activeID)
		.navigationTitle("Shows")
		.navigationBarTitleDisplayMode(.inline)
		.fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
			guard let url = try? result.get() else { return }
			isRefused = !shows.adopt(contentsOf: url)
		}
		.fileExporter(isPresented: Binding { exporting != nil } set: { _ in exporting = nil }, item: exporting, contentTypes: [.json], defaultFilename: exporting?.name) { _ in }
		.alert("Can't Import This Show", isPresented: $isRefused) {
			Button("OK", role: .cancel) {}
		} message: {
			Text("It is not a Glow show, or it was written by a different version of Glow.")
		}
		.alert("Delete Show?", isPresented: Binding { deleting != nil } set: { _ in deleting = nil }, presenting: deleting) { show in
			Button("Cancel", role: .cancel) {}
			
			Button("Delete", role: .destructive) {
				shows.delete(show)
			}
		} message: { show in
			Text("\(show.name) goes with its patch, groups, built fixtures and scenes. There is no undo.")
		}
		.alert("New Show", isPresented: $isNaming) {
			TextField("Name", text: $newName)
				.autocorrectionDisabled()
			
			Button("Cancel", role: .cancel) {}
			
			Button("Create") {
				shows.create(name: newName.trimmingCharacters(in: .whitespaces))
			}
			.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
		}
		.alert("Rename Show", isPresented: Binding { renaming != nil } set: { _ in renaming = nil }, presenting: renaming) { show in
			TextField("Name", text: $renamed)
				.autocorrectionDisabled()
			
			Button("Cancel", role: .cancel) {}
			
			Button("Rename") {
				shows.rename(show, to: renamed.trimmingCharacters(in: .whitespaces))
			}
			.disabled(renamed.trimmingCharacters(in: .whitespaces).isEmpty)
		}
	}
}
