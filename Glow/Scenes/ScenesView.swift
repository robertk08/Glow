import SwiftData
import SwiftUI

struct ScenesView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@State private var isNaming = false
	@State private var newName = ""
	@State private var recalled: PersistentIdentifier?
	
	var body: some View {
		List {
			Section {
				ForEach(looks) { look in
					Button {
						console.recall(look, among: fixtures)
						recalled = look.persistentModelID
					} label: {
						LabeledContent {
							Text("^[\(look.fixtureCount) light](inflect: true)")
								.font(.subheadline)
								.foregroundStyle(.secondary)
						} label: {
							Label(look.name, systemImage: "theatermasks")
						}
						.contentShape(.rect)
					}
					.buttonStyle(.plain)
					.swipeActions {
						Button("Delete", systemImage: "trash", role: .destructive) {
							context.delete(look)
						}
					}
				}
				.reorderable()
			}
			.reorderContainer(for: Look.self) { difference in
				console.move(difference, among: looks, sortIndex: \.sortIndex)
			}
		}
		.navigationTitle("Scenes")
		.overlay {
			if looks.isEmpty {
				ContentUnavailableView {
					Label("No Scenes Yet", systemImage: "theatermasks")
				} description: {
					Text("A scene stores where every patched light is and puts it back on one tap.")
				}
			}
		}
		.toolbar {
			LinkStatusButton()
			
			ToolbarItem(placement: .topBarTrailing) {
				Button("Save This Look", systemImage: "plus") {
					newName = ""
					isNaming = true
				}
				.disabled(fixtures.isEmpty)
			}
		}
		.sheet(isPresented: $isNaming) {
			NameSheet(title: "Save This Look", prompt: "Scene", hint: "Keeps every light exactly where it is right now, so re-addressing one later does not break the scene.", name: $newName) { name in
				context.insert(Look(name: name, sortIndex: Console.nextSortIndex(looks, sortIndex: \.sortIndex), levels: console.levels(among: fixtures, library: library)))
			}
		}
		.sensoryFeedback(.success, trigger: recalled)
	}
}
