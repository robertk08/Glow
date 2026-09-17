import SwiftData
import SwiftUI

struct ScenesView: View {
	@Environment(Console.self) private var console
	@Environment(\.modelContext) private var context
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	
	@State private var isNaming = false
	@State private var newName = ""
	@State private var recalled: PersistentIdentifier?
	
	var body: some View {
		NavigationStack {
			List {
				ForEach(looks) { look in
					Button {
						console.recall(look)
						recalled = look.persistentModelID
					} label: {
						LabeledContent {
							Text("\(look.litCount) channels")
								.monospacedDigit()
								.foregroundStyle(.secondary)
						} label: {
							Label(look.name, systemImage: "theatermasks")
						}
						.contentShape(.rect)
					}
					.buttonStyle(.plain)
				}
				.onDelete { offsets in
					for index in offsets {
						context.delete(looks[index])
					}
				}
				.onMove { source, destination in
					var ordered = looks
					ordered.move(fromOffsets: source, toOffset: destination)
					
					for (index, look) in ordered.enumerated() {
						look.sortIndex = index
					}
				}
			}
			.navigationTitle("Scenes")
			.overlay {
				if looks.isEmpty {
					ContentUnavailableView {
						Label("No Scenes Yet", systemImage: "theatermasks")
					} description: {
						Text("Set your lights the way you want them, then keep the look here to bring it back with one tap.")
					} actions: {
						Button("Save This Look", systemImage: "plus") {
							newName = ""
							isNaming = true
						}
						.font(.headline)
						.buttonStyle(.glassProminent)
						.controlSize(.large)
					}
				}
			}
			.toolbar {
				SettingsToolbarButton()
				
				ToolbarItem(placement: .topBarTrailing) {
					EditButton()
				}
				
				ToolbarItem(placement: .topBarTrailing) {
					Button("Save This Look", systemImage: "plus") {
						newName = ""
						isNaming = true
					}
					.alert("Save This Look", isPresented: $isNaming) {
						TextField("Name", text: $newName)
						Button("Cancel", role: .cancel) {}
						Button("Save") {
							let name = newName.trimmingCharacters(in: .whitespaces)
							guard !name.isEmpty else { return }
							context.insert(Look(name: name, sortIndex: (looks.map(\.sortIndex).max() ?? 0) + 1, values: console.universe.values))
						}
					} message: {
						Text("Keeps every channel exactly where it is right now.")
					}
				}
			}
			.sensoryFeedback(.success, trigger: recalled)
		}
	}
}
