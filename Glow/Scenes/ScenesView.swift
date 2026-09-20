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
	@State private var renaming: Look?
	@State private var renamed = ""
	
	var body: some View {
		List {
			ForEach(looks) { look in
				Button {
					console.recall(look, among: fixtures)
				} label: {
					LabeledContent {
						Text("^[\(look.fixtureCount) light](inflect: true)")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					} label: {
						Label(look.name, systemImage: console.activeScene == look.identifier ? "theatermasks.fill" : "theatermasks")
							.foregroundStyle(console.activeScene == look.identifier ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
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
					Button("New Scene", systemImage: "plus") {
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
				Button("New Scene", systemImage: "plus") {
					newName = ""
					isNaming = true
				}
				.disabled(fixtures.isEmpty)
			}
		}
		.alert("New Scene", isPresented: $isNaming) {
			TextField("Name", text: $newName)
				.autocorrectionDisabled()
			
			Button("Cancel", role: .cancel) {}
			
			Button("Save") {
				context.insert(Look(name: newName.trimmingCharacters(in: .whitespaces), sortIndex: Console.nextSortIndex(looks, sortIndex: \.sortIndex), levels: console.levels(among: fixtures, library: library)))
			}
			.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
		}
		.alert("Rename Scene", isPresented: Binding { renaming != nil } set: { _ in renaming = nil }, presenting: renaming) { look in
			TextField("Name", text: $renamed)
				.autocorrectionDisabled()
			
			Button("Cancel", role: .cancel) {}
			
			Button("Rename") {
				look.name = renamed.trimmingCharacters(in: .whitespaces)
			}
			.disabled(renamed.trimmingCharacters(in: .whitespaces).isEmpty)
		}
		.sensoryFeedback(.success, trigger: console.activeScene)
	}
}
