import SwiftData
import SwiftUI

struct CueEditView: View {
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	
	@State private var identifier: String
	
	init(cue: Cue) {
		_identifier = State(initialValue: cue.identifier)
	}
	
	var body: some View {
		NavigationStack {
			if let cue = cues.first(where: { $0.identifier == identifier }) {
				let held = looks.first { $0.identifier == cue.lookID }?.cues(among: cues) ?? [cue]
				
				CueForm(cue: cue, held: held, identifier: $identifier)
					.id(cue.identifier)
			}
		}
	}
}

private struct CueForm: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	
	@Bindable var cue: Cue
	
	let held: [Cue]
	
	@Binding var identifier: String
	
	@State private var recording: Recording?
	@State private var isDeleting = false
	@State private var original: Levels
	@State private var lights: Set<String>
	@State private var features = Set(FeatureGroup.allCases)
	@FocusState private var isLabelling: Bool
	
	init(cue: Cue, held: [Cue], identifier: Binding<String>) {
		self.cue = cue
		self.held = held
		_identifier = identifier
		_original = State(initialValue: cue.levels)
		_lights = State(initialValue: Set(cue.levels.lights.keys))
	}
	
	var body: some View {
		let position = held.firstIndex { $0.identifier == cue.identifier } ?? 0
		let types = Dictionary(fixtures.compactMap { fixture in library.type(fixture.typeID).map { (fixture.identifier, $0) } }, uniquingKeysWith: { first, _ in first })
		let stored = fixtures.filter { original.lights[$0.identifier] != nil }
		let aspects = FeatureGroup.allCases.filter { group in stored.contains { original.features(of: $0.identifier, type: types[$0.identifier]).contains(group) } }
		let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
		
		Form {
			Section {
				TextField("Name", text: $cue.label)
					.submitLabel(.done)
					.focused($isLabelling)
			}
			
			Section {
				CueTiming(fade: $cue.fade, delay: $cue.delay, follow: $cue.follow)
			}
			
			Section {
				LazyVGrid(columns: columns, spacing: 8) {
					ForEach(aspects) { feature in
						Toggle(isOn: Binding { features.contains(feature) } set: { isOn in
							if isOn {
								features.insert(feature)
							} else {
								features.remove(feature)
							}
							
							cue.levels = original.keeping(lights, features: features, types: types)
						}) {
							HStack(spacing: 6) {
								Image(systemName: feature.symbol)
								
								Text(feature.name)
							}
							.font(.subheadline)
							.lineLimit(1)
							.minimumScaleFactor(0.8)
							.frame(maxWidth: .infinity)
						}
					}
				}
				.toggleStyle(.button)
				.buttonStyle(.glass)
				.buttonBorderShape(.capsule)
				.padding(.vertical, 4)
			} header: {
				Text("Stored")
			}
			
			Section {
				if groups.contains(where: { group in group.members.contains { original.lights[$0.identifier] != nil } }) {
					LazyVGrid(columns: columns, spacing: 8) {
						ForEach(groups.filter { group in group.members.contains { original.lights[$0.identifier] != nil } }) { group in
							let members = Set(group.members.map(\.identifier)).intersection(original.lights.keys)
							
							Toggle(isOn: Binding { members.isSubset(of: lights) } set: { isOn in
								if isOn {
									lights.formUnion(members)
								} else {
									lights.subtract(members)
								}
								
								cue.levels = original.keeping(lights, features: features, types: types)
							}) {
								HStack(spacing: 6) {
									Image(systemName: group.symbol)
									
									Text(group.name)
								}
								.font(.subheadline)
								.lineLimit(1)
								.minimumScaleFactor(0.8)
								.frame(maxWidth: .infinity)
							}
							.tint(group.tint.color ?? .accentColor)
						}
					}
					.toggleStyle(.button)
					.buttonStyle(.glass)
					.buttonBorderShape(.capsule)
					.padding(.vertical, 4)
				}
				
				ForEach(stored) { fixture in
					Toggle(isOn: Binding { lights.contains(fixture.identifier) } set: { isOn in
						if isOn {
							lights.insert(fixture.identifier)
						} else {
							lights.remove(fixture.identifier)
						}
						
						cue.levels = original.keeping(lights, features: features, types: types)
					}) {
						Label(fixture.name, systemImage: fixture.symbol(library.type(fixture.typeID)))
					}
				}
			} header: {
				Text("Lights")
			}
			
			Section {
				Button("Update from Stage", systemImage: "arrow.triangle.2.circlepath") {
					recording = Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
				}
				.disabled(!Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).isReady)
				.foregroundStyle(.tint)
			}
			
			Section {
				Button("Delete Cue", systemImage: "trash", role: .destructive) {
					isDeleting = true
				}
				.foregroundStyle(.red)
				.confirmationDialog("Delete Cue \(position + 1)?", isPresented: $isDeleting, titleVisibility: .visible) {
					Button("Delete Cue", role: .destructive) {
						if let look = looks.first(where: { $0.identifier == cue.lookID }) {
							console.delete([cue], from: CueList(look, cues: cues, fixtures: fixtures), context: context)
						}
						
						dismiss()
					}
				}
			}
		}
		.scrollDismissesKeyboard(.interactively)
		.navigationTitle("Cue \(position + 1)")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItemGroup(placement: .topBarLeading) {
				Button("Previous Cue", systemImage: "chevron.up") {
					identifier = held[position - 1].identifier
				}
				.disabled(position == 0)
				
				Button("Next Cue", systemImage: "chevron.down") {
					identifier = held[position + 1].identifier
				}
				.disabled(position >= held.count - 1)
			}
			
			ToolbarItem(placement: .confirmationAction) {
				Button(role: .confirm) {
					dismiss()
				}
			}
		}
		.sheet(item: $recording) {
			original = cue.levels
			lights = Set(cue.levels.lights.keys)
			features = Set(FeatureGroup.allCases)
		} content: { recording in
			StoreView(recording: recording)
		}
		.sensoryFeedback(.selection, trigger: lights)
		.sensoryFeedback(.selection, trigger: features)
		.onChange(of: isLabelling) {
			if !isLabelling, !cue.isDeleted, cue.modelContext != nil { cue.settleLabel() }
		}
		.onDisappear {
			if !cue.isDeleted, cue.modelContext != nil { cue.settleLabel() }
		}
	}
}
