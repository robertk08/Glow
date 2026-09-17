import SwiftData
import SwiftUI

struct LightsView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Environment(ShowLibrary.self) private var shows
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	
	@State private var isAdding = false
	@State private var showsProgrammer = false
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
	
	private var lights: some View {
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
					LightRow(fixture: fixture, clashes: clashing.contains(fixture.persistentModelID))
						.contentShape(.rect)
						.onTapGesture {
							console.toggle(fixture)
						}
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
			
			if sizeClass == .regular {
				SceneSections()
			}
		}
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
			
			if sizeClass == .compact, !console.selection.isEmpty {
				ToolbarItem(placement: .topBarTrailing) {
					Button("Programmer", systemImage: "slider.horizontal.3") {
						showsProgrammer = true
					}
				}
			}
			
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
		.sensoryFeedback(.selection, trigger: console.selection)
		.onChange(of: fixtures) {
			console.applyPatch(fixtures, library: library)
		}
		.task {
			console.applyPatch(fixtures, library: library)
		}
	}
	
	var body: some View {
		if sizeClass == .regular {
			NavigationSplitView {
				lights
					.navigationTitle(shows.active.name)
					.navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 460)
					.safeAreaInset(edge: .bottom) {
						MasterBar()
							.padding(.vertical, 10)
							.background(.bar)
					}
			} detail: {
				if console.selection.isEmpty {
					ContentUnavailableView {
						Label("Nothing Selected", systemImage: "slider.horizontal.3")
					} description: {
						Text("Tap one or more lights to take control of them.")
					}
				} else {
					ControlSheet(control: console.control(among: fixtures, library: library))
				}
			}
		} else {
			NavigationStack {
				lights
					.navigationTitle("Lights")
			}
			.sheet(isPresented: $showsProgrammer) {
				ControlSheet(control: console.control(among: fixtures, library: library))
					.presentationDetents([.height(200), .medium, .large])
					.presentationBackgroundInteraction(.enabled)
			}
			.onChange(of: console.selection.isEmpty) { _, isEmpty in
				showsProgrammer = !isEmpty
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
		guard let control, control.isOn else { return Color(.tertiarySystemFill) }
		if let tint = fixture.tint.color { return tint }
		guard control.mixesColor else { return .accentColor }
		return control.displayColor
	}
	
	private var inkColor: Color {
		guard let control, control.isOn else { return .secondary }
		guard fixture.tint.color == nil, control.mixesColor else { return .white }
		return control.displayInk
	}
	
	var body: some View {
		LabeledContent {
			HStack(spacing: 6) {
				if let control, control.dims {
					Text(control.brightness, format: .percent.precision(.fractionLength(0)))
						.font(.subheadline.monospacedDigit())
						.foregroundStyle(.secondary)
				}
				
				if console.isSelected(fixture) {
					Image(systemName: "checkmark.circle.fill")
						.foregroundStyle(.tint)
				}
			}
		} label: {
			Label {
				VStack(alignment: .leading, spacing: 2) {
					Text(fixture.name)
					
					if clashes {
						Text("Address \(fixture.rangeLabel(profile)) · overlaps")
							.font(.caption)
							.foregroundStyle(.orange)
					} else {
						Text("Address \(fixture.rangeLabel(profile))")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			} icon: {
				Button {
					control?.toggleOn()
				} label: {
					Image(systemName: fixture.symbol(profile))
						.font(.callout)
						.foregroundStyle(inkColor)
						.frame(width: 36, height: 36)
						.background(iconColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
						.overlay {
							RoundedRectangle(cornerRadius: 11, style: .continuous)
								.strokeBorder(.secondary.opacity(0.55))
						}
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.vertical, 4)
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
			}
		} label: {
			Label {
				VStack(alignment: .leading, spacing: 2) {
					Text(group.name)
					
					Text("^[\(group.members.count) light](inflect: true)")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			} icon: {
				Image(systemName: group.symbol)
					.font(.callout)
					.foregroundStyle(.white)
					.frame(width: 36, height: 36)
					.background(group.tint.color ?? .accentColor, in: .circle)
					.overlay {
						Circle()
							.strokeBorder(.secondary.opacity(0.55))
					}
			}
		}
		.padding(.vertical, 4)
	}
}
