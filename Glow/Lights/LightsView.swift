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
	
	private var grid: some View {
		ScrollView {
			if !groups.isEmpty {
				ScrollView(.horizontal) {
					HStack(spacing: 8) {
						ForEach(groups) { group in
							GroupChip(group: group, editing: $editingGroup)
						}
						.reorderable()
					}
					.padding(.horizontal)
					.padding(.vertical, 4)
					.reorderContainer(for: FixtureGroup.self) { difference in
						console.move(difference, among: groups, sortIndex: \.sortIndex)
					}
				}
				.scrollIndicators(.hidden)
				.padding(.bottom, 10)
			}
			
			GlassEffectContainer(spacing: 12) {
				LazyVGrid(columns: columns, spacing: 12) {
					ForEach(fixtures) { fixture in
						LightTile(fixture: fixture, clashes: clashing.contains(fixture.persistentModelID), editing: $editingFixture)
					}
					.reorderable()
				}
			}
			.padding(.horizontal)
			.reorderContainer(for: Fixture.self) { difference in
				console.move(difference, among: fixtures, sortIndex: \.sortIndex)
			}
			
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
		.accessibilityValue("^[\(group.members.count) light](inflect: true)")
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
