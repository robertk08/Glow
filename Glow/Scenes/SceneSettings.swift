import SwiftData
import SwiftUI

struct SceneSettings: View {
	@Environment(Console.self) private var console
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@Environment(Arrangement.self) private var arrangement
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var look: Look
	
	@State private var isDeleting = false
	@State private var named = ""
	@FocusState private var isNaming: Bool
	
	var body: some View {
		NavigationStack {
			if !look.isGone {
				content
			}
		}
	}
	
	@ViewBuilder private var content: some View {
		let tint = look.tint.color ?? .accentColor
		let list = CueList(look, cues: cues, fixtures: fixtures)
		let tile = arrangement.frame(of: look.size, among: looks)
		
		Form {
			Section {
				TextField("Name", text: $look.name)
					.autocorrectionDisabled()
					.submitLabel(.done)
					.focused($isNaming)
			} header: {
				SceneFace(look: look, list: list)
					.overlay {
						TileControls(look: look, list: list)
					}
					.frame(width: tile?.width, height: tile?.height)
					.frame(maxWidth: .infinity)
					.padding(.top, 8)
					.padding(.bottom, 28)
					.foregroundStyle(.primary)
					.textCase(nil)
					.allowsHitTesting(false)
					.accessibilityHidden(true)
			}
			
			Section {
				Picker("Size", selection: Binding { look.size } set: { arrangement.resize(look, to: $0, among: looks) }) {
					ForEach(TileSize.allCases) { size in
						Text(size.name)
							.tag(size)
					}
				}
				.pickerStyle(.segmented)
				
				Picker("Tap", selection: $look.tap) {
					ForEach(SceneAction.allCases) { action in
						Label(action.name, systemImage: action.symbol)
							.tag(action)
					}
				}
			}
			
			if look.size != .small {
				Section {
					ForEach(look.buttons) { action in
						SceneButtonRow(action: action, isOn: true, tint: tint) {
							look.shows(action, false)
						}
					}
					.onMove { from, to in
						look.buttons.move(fromOffsets: from, toOffset: to)
					}
					
					ForEach(SceneAction.allCases.filter { !look.buttons.contains($0) }) { action in
						SceneButtonRow(action: action, isOn: false, tint: tint) {
							look.shows(action, true)
						}
					}
				} header: {
					Text("Buttons")
				}
			}
			
			Section {
				AppearancePicker(symbol: Binding { look.symbol } set: { look.symbolOverride = $0 }, tint: $look.tint)
			} header: {
				Text("Icon and Colour")
			}
			
			Section {
				Button("Delete Scene", systemImage: "trash", role: .destructive) {
					isDeleting = true
				}
				.foregroundStyle(.red)
				.confirmationDialog("Delete \(look.name)?", isPresented: $isDeleting, titleVisibility: .visible) {
					Button("Delete Scene", role: .destructive) {
						console.remove(look, with: cues, context: context)
						dismiss()
					}
				}
			}
		}
		.animation(.snappy(duration: 0.3), value: look.buttons)
		.animation(.snappy(duration: 0.3), value: look.size)
		.navigationTitle(look.name)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .confirmationAction) {
				Button(role: .confirm) {
					dismiss()
				}
			}
		}
		.onAppear {
			named = look.name
		}
		.onChange(of: isNaming) {
			if isNaming {
				named = look.name
			} else {
				look.settle(name: named, among: looks)
			}
		}
		.onDisappear {
			if !look.isGone { look.settle(name: named, among: looks) }
		}
	}
}

private struct SceneButtonRow: View {
	let action: SceneAction
	let isOn: Bool
	let tint: Color
	let toggle: () -> Void
	
	var body: some View {
		Button(action: toggle) {
			HStack(spacing: 16) {
				Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
					.font(.title3)
					.foregroundStyle(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
				
				Label(action.name, systemImage: action.symbol)
					.foregroundStyle(isOn ? .primary : .secondary)
				
				Spacer(minLength: 0)
				
				if isOn {
					Image(systemName: "line.3.horizontal")
						.foregroundStyle(.tertiary)
				}
			}
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(isOn ? .isSelected : [])
	}
}
