import SwiftUI
import UniformTypeIdentifiers

struct ShowsView: View {
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
						shows.activate(show)
					} label: {
						LabeledContent {
							Image(systemName: "checkmark")
								.foregroundStyle(.tint)
								.opacity(show.id == shows.activeID ? 1 : 0)
						} label: {
							Label(show.name, systemImage: "theatermasks.circle")
						}
						.contentShape(.rect)
					}
					.buttonStyle(.plain)
					.accessibilityAddTraits(show.id == shows.activeID ? [.isSelected] : [])
					.swipeActions {
						Button("Delete", systemImage: "trash", role: .destructive) {
							deleting = show
						}
						.disabled(shows.shows.count < 2)
					}
					.contextMenu {
						Button("Rename", systemImage: "pencil") {
							renaming = show
							renamed = show.name
						}
						
						Button("Duplicate", systemImage: "plus.square.on.square") {
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
				}
			} footer: {
				Text("Switching show swaps the whole store, so a house rig and a touring rig never see each other. The controller you send to stays with this device.")
			}
			
			Section {
				Button("Import Show", systemImage: "square.and.arrow.down") {
					isImporting = true
				}
				
				Button("New Show", systemImage: "plus") {
					newName = ""
					isNaming = true
				}
			} footer: {
				Text("Hold a show for Share, Duplicate and Save to Files.")
			}
		}
		.sensoryFeedback(.selection, trigger: shows.activeID)
		.navigationTitle("Shows")
		.navigationBarTitleDisplayMode(.inline)
		.fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
			guard let url = try? result.get() else { return }
			shows.adopt(contentsOf: url)
		}
		.fileExporter(isPresented: Binding { exporting != nil } set: { _ in exporting = nil }, document: exporting, contentType: .json, defaultFilename: exporting?.show.name) { _ in }
		.sheet(isPresented: $isNaming) {
			NameSheet(title: "New Show", prompt: "Show", hint: "Starts empty, and switches to it.", name: $newName) { name in
				shows.create(name: name)
			}
		}
		.sheet(item: $renaming) { show in
			NameSheet(title: "Rename Show", prompt: "Show", name: $renamed) { name in
				shows.rename(show, to: name)
			}
		}
		.confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding { deleting != nil } set: { _ in deleting = nil }, titleVisibility: .visible) {
			Button("Delete Show", role: .destructive) {
				if let deleting {
					shows.delete(deleting)
				}
				deleting = nil
			}
		} message: {
			Text("Its patch, groups, built fixtures and scenes go with it, and there is no undo.")
		}
	}
}
