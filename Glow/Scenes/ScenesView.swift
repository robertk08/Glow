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
	@State private var renaming: Look?
	@State private var renamed = ""
	
	var body: some View {
		List {
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
						Label(look.name, systemImage: recalled == look.persistentModelID ? "theatermasks.fill" : "theatermasks")
							.foregroundStyle(recalled == look.persistentModelID ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
					}
					.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.swipeActions(edge: .trailing) {
					Button("Delete", systemImage: "trash", role: .destructive) {
						context.delete(look)
					}
				}
				.swipeActions(edge: .leading) {
					Button("Rename", systemImage: "pencil") {
						renaming = look
						renamed = look.name
					}
					.tint(.indigo)
				}
			}
			.onMove {
				console.move($0, to: $1, among: looks, sortIndex: \.sortIndex)
			}
		}
		.navigationTitle("Scenes")
		.overlay {
			if looks.isEmpty {
				ContentUnavailableView {
					Label("No Scenes Yet", systemImage: "theatermasks")
				} description: {
					Text(fixtures.isEmpty ? "Patch a light first, set it how you want it, then save the look here." : "Set the rig how you want it, then save the look here. A scene records lights rather than addresses, so re-addressing one later does not break it.")
				} actions: {
					Button("Save This Look", systemImage: "plus") {
						newName = ""
						isNaming = true
					}
					.font(.headline)
					.buttonStyle(.glassProminent)
					.controlSize(.large)
					.disabled(fixtures.isEmpty)
				}
			}
		}
		.toolbar {
			LinkStatusButton()
			
			ToolbarSpacer(.flexible, placement: .topBarTrailing)
			
			ToolbarItem(placement: .topBarTrailing) {
				EditButton()
					.disabled(looks.isEmpty)
			}
			
			ToolbarSpacer(.fixed, placement: .topBarTrailing)
			
			ToolbarItem(placement: .topBarTrailing) {
				Button("Save This Look", systemImage: "plus") {
					newName = ""
					isNaming = true
				}
				.disabled(fixtures.isEmpty)
			}
		}
		.sheet(isPresented: $isNaming) {
			NameSheet(title: "Save This Look", prompt: "Scene", hint: "Keeps every light exactly where it is right now.", name: $newName) { name in
				context.insert(Look(name: name, sortIndex: Console.nextSortIndex(looks, sortIndex: \.sortIndex), levels: console.levels(among: fixtures, library: library)))
			}
		}
		.sheet(item: $renaming) { look in
			NameSheet(title: "Rename Scene", prompt: "Scene", name: $renamed) { name in
				look.name = name
			}
		}
		.sensoryFeedback(.success, trigger: recalled)
	}
}
