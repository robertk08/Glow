import SwiftData
import SwiftUI

struct LightsView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	
	@State private var isAdding = false
	@State private var newGroupName = ""
	@State private var isNamingGroup = false
	
	private var ungrouped: [Fixture] {
		fixtures.filter { $0.group == nil }
	}
	
	var body: some View {
		@Bindable var console = console
		
		NavigationStack {
			List {
				if !fixtures.isEmpty {
					Section("All Lights") {
						Slider(value: $console.master, in: 0...1) {
							Text("Brightness")
						} minimumValueLabel: {
							Image(systemName: "sun.min")
						} maximumValueLabel: {
							Image(systemName: "sun.max")
						}
						
						Label("Hold for Blackout", systemImage: "power")
							.foregroundStyle(console.blackout ? Color.red : Color.primary)
							.contentShape(.rect)
							.gesture(DragGesture(minimumDistance: 0).onChanged { _ in
								guard !console.blackout else { return }
								Haptic.feedback(.heavy)
								console.blackout = true
							}.onEnded { _ in
								console.blackout = false
							})
					}
				}
				
				if !groups.isEmpty {
					Section("Groups") {
						ForEach(groups) { group in
							NavigationLink {
								GroupView(group: group)
							} label: {
								GroupRow(group: group)
							}
						}
						.onDelete { offsets in
							for index in offsets {
								context.delete(groups[index])
							}
						}
						.onMove { source, destination in
							var ordered = groups
							ordered.move(fromOffsets: source, toOffset: destination)
							
							for (index, group) in ordered.enumerated() {
								group.sortIndex = index
							}
						}
					}
				}
				
				if !ungrouped.isEmpty {
					Section(groups.isEmpty ? "" : "Other Lights") {
						ForEach(ungrouped) { fixture in
							NavigationLink {
								FixtureView(fixture: fixture)
							} label: {
								LightRow(fixture: fixture)
							}
						}
						.onDelete { offsets in
							for index in offsets {
								context.delete(ungrouped[index])
							}
						}
						.onMove { source, destination in
							var ordered = ungrouped
							ordered.move(fromOffsets: source, toOffset: destination)
							
							for (index, fixture) in ordered.enumerated() {
								fixture.sortIndex = index
							}
						}
					}
				}
			}
			.navigationTitle("Lights")
			.overlay {
				if fixtures.isEmpty {
					EmptyStateView(state: .lights) {
						Haptic.feedback(.rigid)
						isAdding = true
					}
				}
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					EditButton()
				}
				
				ToolbarItem(placement: .topBarTrailing) {
					Menu {
						Button("Add Light", systemImage: "plus") {
							Haptic.feedback(.rigid)
							isAdding = true
						}
						
						Button("New Group", systemImage: "square.stack.3d.up") {
							Haptic.feedback(.rigid)
							newGroupName = ""
							isNamingGroup = true
						}
					} label: {
						Image(systemName: "plus")
					}
				}
			}
			.sheet(isPresented: $isAdding) {
				AddLightView(isPresented: $isAdding)
			}
			.alert("New Group", isPresented: $isNamingGroup) {
				TextField("Name", text: $newGroupName)
				Button("Cancel", role: .cancel) {}
				Button("Create") {
					let name = newGroupName.trimmingCharacters(in: .whitespaces)
					guard !name.isEmpty else { return }
					context.insert(FixtureGroup(name: name, sortIndex: (groups.map(\.sortIndex).max() ?? 0) + 1))
				}
			}
			.onChange(of: fixtures) {
				console.applyPatch(fixtures, library: library)
			}
			.task {
				console.applyPatch(fixtures, library: library)
			}
		}
	}
}

struct LightRow: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	
	let fixture: Fixture
	
	private var profile: FixtureProfile? { library.profile(fixture.profileID) }
	
	private var control: FixtureControl? { FixtureControl(fixture: fixture, library: library, console: console) }
	
	private var iconColor: Color {
		if let tint = fixture.tint.color { return tint }
		guard let control, control.profile.mixesColor else { return .accentColor }
		return control.displayColor
	}
	
	var body: some View {
		LabeledContent {
			if let control, control.dims {
				Text(control.brightness, format: .percent.precision(.fractionLength(0)))
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
		} label: {
			Label {
				VStack(alignment: .leading) {
					Text(fixture.name)
					Text("Address \(fixture.address)")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			} icon: {
				Image(systemName: fixture.symbol(profile))
					.foregroundStyle(iconColor)
			}
		}
	}
}

struct GroupRow: View {
	let group: FixtureGroup
	
	var body: some View {
		LabeledContent {
			Text("\(group.members.count)")
				.monospacedDigit()
				.foregroundStyle(.secondary)
		} label: {
			Label {
				Text(group.name)
			} icon: {
				Image(systemName: group.symbol)
					.foregroundStyle(group.tint.color ?? .accentColor)
			}
		}
	}
}
