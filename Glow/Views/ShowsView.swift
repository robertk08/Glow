import SwiftUI

struct ShowsView: View {
	@Environment(ShowLibrary.self) private var shows
	
	@State private var isNaming = false
	@State private var newName = ""
	@State private var renaming: Show?
	@State private var renamed = ""
	
	var body: some View {
		List {
			Section {
				ForEach(shows.shows) { show in
					LabeledContent {
						if show.id == shows.activeID {
							Image(systemName: "checkmark.circle.fill")
								.foregroundStyle(.tint)
						}
					} label: {
						Label(show.name, systemImage: "theatermasks.circle")
					}
					.contentShape(.rect)
					.onTapGesture {
						shows.activate(show)
					}
					.swipeActions {
						Button("Delete", systemImage: "trash", role: .destructive) {
							shows.delete(show)
						}
						.disabled(shows.shows.count < 2)
						
						Button("Rename", systemImage: "pencil") {
							renaming = show
							renamed = show.name
						}
						.tint(.accentColor)
					}
				}
			} footer: {
				Text("A show holds its own patch, groups, built fixtures and scenes. The controller you send to stays with this device.")
			}
			
			Section {
				Button("New Show", systemImage: "plus") {
					newName = ""
					isNaming = true
				}
				.alert("New Show", isPresented: $isNaming) {
					TextField("Name", text: $newName)
					Button("Cancel", role: .cancel) {}
					Button("Create") {
						let name = newName.trimmingCharacters(in: .whitespaces)
						guard !name.isEmpty else { return }
						shows.create(name: name)
					}
				} message: {
					Text("Starts empty, and switches to it.")
				}
			}
		}
		.navigationTitle("Shows")
		.navigationBarTitleDisplayMode(.inline)
		.alert("Rename Show", isPresented: Binding { renaming != nil } set: { _ in renaming = nil }) {
			TextField("Name", text: $renamed)
			Button("Cancel", role: .cancel) { renaming = nil }
			Button("Rename") {
				let name = renamed.trimmingCharacters(in: .whitespaces)
				if let renaming, !name.isEmpty {
					shows.rename(renaming, to: name)
				}
				renaming = nil
			}
		}
	}
}
