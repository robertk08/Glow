import SwiftData
import SwiftUI

struct LightsView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	
	@State private var isAdding = false
	@State private var isNamingGroup = false
	@State private var newGroupName = ""
	@State private var editingFixture: Fixture?
	@State private var editingGroup: FixtureGroup?
	
	private var clashing: Set<PersistentIdentifier> {
		Fixture.clashing(among: fixtures, library: library)
	}
	
	private var used: Int {
		fixtures.reduce(0) { $0 + (library.profile($1.profileID)?.channelCount ?? 0) }
	}
	
	var body: some View {
		NavigationStack {
			List {
				if !groups.isEmpty {
					Section {
						ForEach(groups) { group in
							Button {
								console.toggle(group)
							} label: {
								GroupRow(group: group)
									.contentShape(.rect)
							}
							.buttonStyle(.plain)
							.listRowBackground(console.isSelected(group) ? Color.accentColor.opacity(0.15) : nil)
							.swipeActions {
								Button("Delete", systemImage: "trash", role: .destructive) {
									context.delete(group)
								}
								
								Button("Edit", systemImage: "slider.horizontal.3") {
									editingGroup = group
								}
								.tint(.accentColor)
							}
						}
						.onMove { source, destination in
							var ordered = groups
							ordered.move(fromOffsets: source, toOffset: destination)
							
							for (index, group) in ordered.enumerated() {
								group.sortIndex = index
							}
						}
					} header: {
						Text("Groups")
					} footer: {
						Text("A group selects its lights in one tap.")
					}
				}
				
				Section {
					ForEach(fixtures) { fixture in
						Button {
							console.toggle(fixture)
						} label: {
							LightRow(fixture: fixture, clashes: clashing.contains(fixture.persistentModelID))
								.contentShape(.rect)
						}
						.buttonStyle(.plain)
						.listRowBackground(console.isSelected(fixture) ? Color.accentColor.opacity(0.15) : nil)
						.swipeActions {
							Button("Delete", systemImage: "trash", role: .destructive) {
								context.delete(fixture)
							}
							
							Button("Edit", systemImage: "slider.horizontal.3") {
								editingFixture = fixture
							}
							.tint(.accentColor)
						}
						.swipeActions(edge: .leading) {
							Button("Duplicate", systemImage: "plus.square.on.square") {
								let width = max(1, library.profile(fixture.profileID)?.channelCount ?? 1)
								let copy = Fixture(profileID: fixture.profileID, name: Fixture.unusedName(fixture.name, among: fixtures), address: DMXAddress(clamping: fixture.address + width), sortIndex: (fixtures.map(\.sortIndex).max() ?? 0) + 1)
								copy.symbolOverride = fixture.symbolOverride
								copy.tintName = fixture.tintName
								context.insert(copy)
							}
							.tint(.accentColor)
						}
					}
					.onMove { source, destination in
						var ordered = fixtures
						ordered.move(fromOffsets: source, toOffset: destination)
						
						for (index, fixture) in ordered.enumerated() {
							fixture.sortIndex = index
						}
					}
				} header: {
					Text(groups.isEmpty ? "" : "Lights")
				} footer: {
					if !fixtures.isEmpty {
						Text("\(used) of 512 channels used.")
					}
				}
			}
			.navigationTitle("Lights")
			.overlay {
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
				}
			}
			.toolbar {
				SettingsToolbarButton()
				
				ToolbarItem(placement: .topBarTrailing) {
					EditButton()
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
				}
			}
			.navigationDestination(item: $editingFixture) { fixture in
				FixtureEditView(fixture: fixture)
			}
			.navigationDestination(item: $editingGroup) { group in
				GroupView(group: group)
			}
			.sheet(isPresented: Binding { !console.selection.isEmpty } set: { shown in
				guard !shown else { return }
				console.selection.removeAll()
			}) {
				ControlSheet(control: console.control(among: fixtures, library: library))
					.presentationDetents([.medium, .large])
					.presentationBackgroundInteraction(.enabled(upThrough: .medium))
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
}

private struct LightRow: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	
	let fixture: Fixture
	let clashes: Bool
	
	private var profile: FixtureProfile? { library.profile(fixture.profileID) }
	
	private var control: FixtureControl? { FixtureControl(fixture: fixture, library: library, console: console) }
	
	private var iconColor: Color {
		if let tint = fixture.tint.color { return tint }
		guard let control, control.profile.mixesColor else { return .accentColor }
		return control.displayColor
	}
	
	private var inkColor: Color {
		guard fixture.tint.color == nil, let control, control.profile.mixesColor else { return .white }
		return control.displayInk
	}
	
	var body: some View {
		LabeledContent {
			if console.isSelected(fixture) {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(.tint)
			} else if let control, control.dims {
				Text(control.brightness, format: .percent.precision(.fractionLength(0)))
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
		} label: {
			Label {
				VStack(alignment: .leading) {
					Text(fixture.name)
					
					if clashes {
						Text("Address \(fixture.address) · overlaps")
							.font(.caption)
							.foregroundStyle(.orange)
					} else {
						Text("Address \(fixture.address)")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			} icon: {
				Image(systemName: fixture.symbol(profile))
					.font(.footnote)
					.foregroundStyle(inkColor)
					.frame(width: 28, height: 28)
					.background(iconColor, in: .circle)
			}
		}
	}
}

private struct GroupRow: View {
	@Environment(Console.self) private var console
	
	let group: FixtureGroup
	
	var body: some View {
		LabeledContent {
			if console.isSelected(group) {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(.tint)
			} else {
				Text("\(group.members.count)")
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
		} label: {
			Label {
				Text(group.name)
			} icon: {
				Image(systemName: group.symbol)
					.font(.footnote)
					.foregroundStyle(.white)
					.frame(width: 28, height: 28)
					.background(group.tint.color ?? .accentColor, in: .circle)
			}
		}
	}
}
