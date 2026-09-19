import SwiftData
import SwiftUI

struct LightsView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(ShowLibrary.self) private var shows
	@Environment(\.modelContext) private var context
	@Environment(\.dynamicTypeSize) private var typeSize
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	
	@State private var isOrdering = false
	@State private var isAdding = false
	@State private var isNamingGroup = false
	@State private var newGroupName = ""
	@State private var editingFixture: Fixture?
	@State private var editingGroup: FixtureGroup?
	@ScaledMetric(relativeTo: .headline) private var tileWidth = 168
	
	private var clashing: Set<PersistentIdentifier> {
		Fixture.clashing(among: fixtures, library: library)
	}
	
	private var columns: [GridItem] {
		[GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 300 : tileWidth), spacing: 12)]
	}
	
	@ViewBuilder private var groupChips: some View {
		let items = ForEach(groups) { group in
			GroupChip(group: group, editing: $editingGroup)
		}
		let chips = HStack(spacing: 8) {
			if #available(iOS 27.0, *) {
				items.reorderable()
			} else {
				items
			}
		}
		.padding(.horizontal)
		.padding(.vertical, 4)
		
		if #available(iOS 27.0, *) {
			chips.reorderContainer(for: FixtureGroup.self) { difference in
				console.move(difference, among: groups, sortIndex: \.sortIndex)
			}
		} else {
			chips
		}
	}
	
	@ViewBuilder private var tiles: some View {
		let items = ForEach(fixtures) { fixture in
			LightTile(fixture: fixture, fixtures: fixtures, clashes: clashing.contains(fixture.persistentModelID), editing: $editingFixture)
		}
		let grid = LazyVGrid(columns: columns, spacing: 12) {
			if #available(iOS 27.0, *) {
				items.reorderable()
			} else {
				items
			}
		}
		.padding(.horizontal)
		
		if #available(iOS 27.0, *) {
			grid.reorderContainer(for: Fixture.self) { difference in
				console.move(difference, among: fixtures, sortIndex: \.sortIndex)
			}
		} else {
			grid
		}
	}
	
	private var grid: some View {
		ScrollView {
			if !groups.isEmpty {
				ScrollView(.horizontal) {
					groupChips
				}
				.scrollIndicators(.hidden)
				.padding(.bottom, 10)
			}
			
			tiles
			
			Text("\(library.channelsUsed(by: fixtures)) of \(Universe.channelCount) channels used.")
				.font(.footnote)
				.foregroundStyle(.secondary)
				.padding(.vertical, 20)
		}
	}
	
	var body: some View {
		Group {
			if fixtures.isEmpty {
				ContentUnavailableView {
					Label("No Lights Yet", systemImage: "lightbulb")
				} description: {
					Text("Add the lights on your DMX line, then tap them to take control.")
				} actions: {
					Button("Add Light", systemImage: "plus") {
						isAdding = true
					}
					.font(.headline)
					.buttonStyle(.glassProminent)
					.controlSize(.large)
				}
			} else {
				grid
			}
		}
		.navigationTitle("Lights")
		.navigationSubtitle(shows.active.name)
		.toolbar {
			LinkStatusButton()
			
			ToolbarItem(placement: .topBarTrailing) {
				Button("Reorder", systemImage: "arrow.up.arrow.down") {
					isOrdering = true
				}
				.disabled(fixtures.isEmpty)
			}
			
			if context.undoManager?.canUndo == true {
				ToolbarItem(placement: .topBarTrailing) {
					Button("Undo", systemImage: "arrow.uturn.backward") {
						context.undoManager?.undo()
					}
				}
			}
			
			ToolbarItem(placement: .topBarTrailing) {
				Menu("Add", systemImage: "plus") {
					Button("Add Light", systemImage: "lightbulb") {
						isAdding = true
					}
					
					Button("New Group", systemImage: "square.stack.3d.up") {
						newGroupName = ""
						isNamingGroup = true
					}
				}
			}
		}
		.sheet(isPresented: $isOrdering) {
			NavigationStack {
				List {
					Section("Lights") {
						ForEach(fixtures) { fixture in
							Label(fixture.name, systemImage: fixture.symbol(library.profile(fixture.profileID)))
						}
						.onMove { console.move($0, to: $1, among: fixtures, sortIndex: \.sortIndex) }
					}
					
					if !groups.isEmpty {
						Section("Groups") {
							ForEach(groups) { group in
								Label(group.name, systemImage: group.symbol)
							}
							.onMove { console.move($0, to: $1, among: groups, sortIndex: \.sortIndex) }
						}
					}
				}
				.environment(\.editMode, .constant(.active))
				.navigationTitle("Reorder")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .confirmationAction) {
						Button("Done") { isOrdering = false }
					}
				}
			}
		}
		.sheet(isPresented: $isAdding) {
			NavigationStack {
				LibraryView(patching: $isAdding)
			}
		}
		.sheet(isPresented: $isNamingGroup) {
			NameSheet(title: "New Group", prompt: "Group", name: $newGroupName) {
				let group = FixtureGroup(name: $0, sortIndex: Console.nextSortIndex(groups, sortIndex: \.sortIndex))
				context.insert(group)
				editingGroup = group
			}
		}
		.navigationDestination(item: $editingFixture) { fixture in
			FixtureEditView(fixture: fixture)
		}
		.navigationDestination(item: $editingGroup) { group in
			GroupView(group: group)
		}
		.sensoryFeedback(.selection, trigger: console.selection)
		.onChange(of: fixtures) {
			console.applyPatch(fixtures, library: library)
		}
		.task {
			console.applyPatch(fixtures, library: library)
		}
	}
}

private struct GroupChip: View {
	@Environment(Console.self) private var console
	@Environment(\.modelContext) private var context
	
	let group: FixtureGroup
	
	@Binding var editing: FixtureGroup?
	
	var body: some View {
		Toggle(isOn: Binding { console.isSelected(group) } set: { _ in console.toggle(group) }) {
			Label(group.name, systemImage: group.symbol)
				.font(.subheadline)
		}
		.toggleStyle(.button)
		.buttonStyle(.glass)
		.buttonBorderShape(.capsule)
		.tint(group.tint.color ?? .accentColor)
		.contextMenu {
			Button("Edit Group", systemImage: "slider.horizontal.3") {
				editing = group
			}
			
			Button("Delete Group", systemImage: "trash", role: .destructive) {
				context.delete(group)
			}
		}
	}
}
