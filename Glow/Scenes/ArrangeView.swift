import SwiftData
import SwiftUI

struct ArrangeView: View {
	@Environment(Console.self) private var console
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@ScaledMetric(relativeTo: .headline) private var height = 64
	
	let columns: Int
	
	@State private var selected: String?
	@State private var dragged: String?
	@State private var landing: Int?
	@State private var width: CGFloat = 0
	@State private var deleting: Look?
	@State private var customizing: Look?
	
	var body: some View {
		let board = Board(columns: columns, looks: looks)
		let spacing: CGFloat = 10
		let cell = CGSize(width: max((width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 0), height: height)
		let chosen = looks.first { $0.identifier == selected }
		let rows = board.rows + 1
		
		NavigationStack {
			ScrollView {
				ZStack(alignment: .topLeading) {
					ForEach(0..<rows * columns, id: \.self) { spot in
						RoundedRectangle(cornerRadius: 16, style: .continuous)
							.strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
							.frame(width: cell.width, height: cell.height)
							.contentShape(.rect)
							.onTapGesture {
								guard let selected else { return }
								var moved = board
								moved.place(selected, at: spot)
								moved.write(to: looks)
							}
							.offset(x: CGFloat(spot % columns) * (cell.width + spacing), y: CGFloat(spot / columns) * (cell.height + spacing))
							.accessibilityLabel("Empty Spot")
							.accessibilityAddTraits(.isButton)
					}
					
					if let dragged, let landing, let size = board.sizes[dragged] {
						let across = CGFloat(min(size.columns, columns))
						let tint = looks.first { $0.identifier == dragged }?.tint.color ?? .accentColor
						
						RoundedRectangle(cornerRadius: 16, style: .continuous)
							.fill(tint.opacity(0.15))
							.strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
							.frame(width: across * cell.width + (across - 1) * spacing, height: CGFloat(size.rows) * cell.height + CGFloat(size.rows - 1) * spacing)
							.offset(x: CGFloat(landing % columns) * (cell.width + spacing), y: CGFloat(landing / columns) * (cell.height + spacing))
							.allowsHitTesting(false)
					}
					
					ForEach(looks) { look in
						let size = board.sizes[look.identifier] ?? look.size
						let origin = board.origins[look.identifier] ?? 0
						let across = CGFloat(min(size.columns, columns))
						let frame = CGSize(width: across * cell.width + (across - 1) * spacing, height: CGFloat(size.rows) * cell.height + CGFloat(size.rows - 1) * spacing)
						
						Block(look: look, isSelected: look.identifier == selected)
							.frame(width: frame.width, height: frame.height)
							.contentShape(.rect(cornerRadius: 16, style: .continuous))
							.onTapGesture {
								selected = selected == look.identifier ? nil : look.identifier
							}
							.draggable(look.identifier) {
								Block(look: look, isSelected: true)
									.frame(width: frame.width, height: frame.height)
							}
							.modifier(DragTracking(scene: look.identifier, dragged: $dragged, landing: $landing))
							.offset(x: CGFloat(origin % columns) * (cell.width + spacing), y: CGFloat(origin / columns) * (cell.height + spacing))
							.opacity(look.identifier == dragged ? 0.4 : 1)
							.accessibilityLabel(look.name)
							.accessibilityValue(size.name)
							.accessibilityAddTraits(look.identifier == selected ? [.isButton, .isSelected] : .isButton)
					}
				}
				.frame(width: width, height: CGFloat(rows) * (cell.height + spacing) - spacing, alignment: .topLeading)
				.dropDestination(for: String.self) { items, session in
					guard let scene = items.first, let origin = board.origin(of: scene, centeredAt: session.location, cell: cell, spacing: spacing) else { return }
					var moved = board
					moved.place(scene, at: origin)
					moved.write(to: looks)
					selected = scene
					dragged = nil
					landing = nil
				}
				.modifier(DropTracking(board: board, dragged: dragged, cell: cell, spacing: spacing, landing: $landing))
				.animation(.snappy(duration: 0.3), value: board)
				.animation(.snappy(duration: 0.2), value: landing)
				.frame(maxWidth: .infinity)
				.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
				.padding()
			}
			.safeAreaBar(edge: .bottom) {
				if let chosen {
					VStack(spacing: 12) {
						Picker("Size", selection: Binding { board.sizes[chosen.identifier] ?? chosen.size } set: { size in
							var resized = board
							resized.resize(chosen.identifier, to: size)
							resized.write(to: looks)
						}) {
							ForEach(TileSize.allCases) { size in
								Text(size.name)
									.tag(size)
							}
						}
						.pickerStyle(.segmented)
						
						HStack {
							Button("Customize", systemImage: "slider.horizontal.3") {
								customizing = chosen
							}
							
							Spacer(minLength: 0)
							
							Button("Delete", systemImage: "trash", role: .destructive) {
								deleting = chosen
							}
							.foregroundStyle(.red)
						}
						.font(.body.weight(.medium))
						.buttonStyle(.plain)
					}
					.padding()
					.glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
					.padding(.horizontal)
					.padding(.bottom, 8)
					.transition(.move(edge: .bottom).combined(with: .opacity))
				}
			}
			.animation(.snappy(duration: 0.25), value: selected)
			.navigationTitle("Edit Scenes")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button(role: .confirm) {
						dismiss()
					}
				}
			}
			.confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } }, titleVisibility: .visible, presenting: deleting) { look in
				Button("Delete Scene", role: .destructive) {
					selected = nil
					console.remove(look, with: cues, context: context)
				}
			}
			.sheet(item: $customizing) { look in
				SceneSettings(look: look)
			}
			.sensoryFeedback(.selection, trigger: selected)
			.sensoryFeedback(.impact(weight: .light), trigger: board)
		}
	}
}

private struct Block: View {
	let look: Look
	let isSelected: Bool
	
	var body: some View {
		let tint = look.tint.color ?? .accentColor
		
		HStack(alignment: .top, spacing: 10) {
			Image(systemName: look.symbol)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(tint)
				.frame(width: 30, height: 30)
				.background(tint.opacity(0.18), in: .circle)
			
			Text(look.name)
				.font(.subheadline.weight(.semibold))
				.lineLimit(2)
				.padding(.top, 5)
			
			Spacer(minLength: 0)
		}
		.padding(10)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.background(.background.secondary, in: .rect(cornerRadius: 16, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.strokeBorder(isSelected ? tint : .clear, lineWidth: 2.5)
		}
	}
}

private struct DragTracking: ViewModifier {
	let scene: String
	
	@Binding var dragged: String?
	@Binding var landing: Int?
	
	func body(content: Content) -> some View {
		if #available(iOS 27, *) {
			content
				.dragConfiguration(DragConfiguration(operationsWithinApp: .init(allowMove: true), operationsOutsideApp: .init(allowCopy: false)))
				.onDragSessionUpdated { session in
					switch session.phase {
					case .initial: dragged = scene
					case .ended:
						dragged = nil
						landing = nil
					default: break
					}
				}
		} else {
			content
		}
	}
}

private struct DropTracking: ViewModifier {
	let board: Board
	let dragged: String?
	let cell: CGSize
	let spacing: CGFloat
	
	@Binding var landing: Int?
	
	func body(content: Content) -> some View {
		if #available(iOS 27, *) {
			content
				.dropConfiguration { _ in
					DropConfiguration(operation: .move)
				}
				.onDropSessionUpdated { session in
					switch session.phase {
					case .entering, .active: landing = dragged.flatMap { board.origin(of: $0, centeredAt: session.location, cell: cell, spacing: spacing) }
					default: landing = nil
					}
				}
		} else {
			content
		}
	}
}
