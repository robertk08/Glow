import SwiftData
import SwiftUI

struct ArrangeView: View {
	@Environment(Console.self) private var console
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	
	let columns: Int
	
	@State private var dragged: String?
	@State private var dropped: String?
	@State private var landing: Int?
	@State private var width: CGFloat = 0
	@State private var height: CGFloat = 76
	@State private var deleting: Look?
	@State private var customizing: Look?
	
	var body: some View {
		let board = Board(columns: columns, looks: looks)
		let spacing: CGFloat = 12
		let cell = CGSize(width: max((width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 0), height: height)
		let rows = board.rows + 1
		
		NavigationStack {
			ScrollView {
				ZStack(alignment: .topLeading) {
					if let first = looks.first {
						Block(look: first)
							.frame(width: cell.width)
							.fixedSize(horizontal: false, vertical: true)
							.hidden()
							.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = max($0 + 20, 76) }
							.accessibilityHidden(true)
					}
					
					ForEach(0..<rows * columns, id: \.self) { spot in
						RoundedRectangle(cornerRadius: 18, style: .continuous)
							.fill(.fill.quaternary)
							.frame(width: cell.width, height: cell.height)
							.offset(x: CGFloat(spot % columns) * (cell.width + spacing), y: CGFloat(spot / columns) * (cell.height + spacing))
							.accessibilityHidden(true)
					}
					
					if let dragged, let landing {
						let frame = board.frame(of: dragged, cell: cell, spacing: spacing)
						let tint = looks.first { $0.identifier == dragged }?.tint.color ?? .accentColor
						
						RoundedRectangle(cornerRadius: 18, style: .continuous)
							.fill(tint.opacity(0.3))
							.frame(width: frame.width, height: frame.height)
							.offset(x: CGFloat(landing % columns) * (cell.width + spacing), y: CGFloat(landing / columns) * (cell.height + spacing))
							.allowsHitTesting(false)
							.transition(.opacity)
					}
					
					ForEach(looks) { look in
						let origin = board.origins[look.identifier] ?? 0
						let frame = board.frame(of: look.identifier, cell: cell, spacing: spacing)
						
						Block(look: look)
							.frame(width: frame.width, height: frame.height)
							.contentShape(.rect(cornerRadius: 18, style: .continuous))
							.contentShape(.dragPreview, .rect(cornerRadius: 18, style: .continuous))
							.contentShape(.contextMenuPreview, .rect(cornerRadius: 18, style: .continuous))
							.onTapGesture {
								customizing = look
							}
							.contextMenu {
								Picker("Size", selection: Binding { board.sizes[look.identifier] ?? look.size } set: { size in
									Task {
										try? await Task.sleep(for: .milliseconds(650))
										var resized = Board(columns: columns, looks: looks)
										resized.resize(look.identifier, to: size)
										dropped = nil
										resized.write(to: looks)
									}
								}) {
									ForEach(TileSize.allCases) { size in
										Text(size.name)
											.tag(size)
									}
								}
								
								Button("Customize", systemImage: "slider.horizontal.3") {
									customizing = look
								}
								
								Button("Delete Scene", systemImage: "trash", role: .destructive) {
									deleting = look
								}
							}
							.draggable(look.identifier)
							.modifier(DragTracking(scene: look.identifier, dragged: $dragged, landing: $landing))
							.opacity(look.identifier == dragged ? 0 : 1)
							.offset(x: CGFloat(origin % columns) * (cell.width + spacing), y: CGFloat(origin / columns) * (cell.height + spacing))
							.animation(look.identifier == dropped ? nil : .smooth(duration: 0.35), value: board)
							.accessibilityLabel(look.name)
							.accessibilityValue(board.sizes[look.identifier]?.name ?? "")
							.accessibilityHint("Customizes it.")
					}
				}
				.frame(width: width, height: max(CGFloat(rows) * (cell.height + spacing) - spacing, 0), alignment: .topLeading)
				.dropDestination(for: String.self) { items, session in
					guard let scene = items.first, let origin = board.origin(of: scene, at: session.location, cell: cell, spacing: spacing) else { return }
					var moved = board
					moved.place(scene, at: origin)
					dropped = scene
					moved.write(to: looks)
					dragged = nil
					landing = nil
				}
				.modifier(DropTracking(board: board, dragged: dragged, cell: cell, spacing: spacing, landing: $landing))
				.animation(.smooth(duration: 0.2), value: landing)
				.frame(maxWidth: .infinity)
				.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
				.padding()
			}
			.background(Color(.systemGroupedBackground))
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
					console.remove(look, with: cues, context: context)
				}
			}
			.sheet(item: $customizing) { look in
				SceneSettings(look: look)
			}
			.sensoryFeedback(.impact(weight: .light), trigger: board)
		}
	}
}

private struct Block: View {
	let look: Look
	
	var body: some View {
		let tint = look.tint.color ?? .accentColor
		
		VStack(alignment: .leading, spacing: 4) {
			Image(systemName: look.symbol)
				.font(.body.weight(.semibold))
				.foregroundStyle(tint)
				.frame(width: 32, height: 32)
				.background(tint.opacity(0.16), in: .circle)
			
			Spacer(minLength: 0)
			
			Text(look.name)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.primary)
				.lineLimit(1)
		}
		.padding(12)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
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
					case .entering, .active: landing = dragged.flatMap { board.origin(of: $0, at: session.location, cell: cell, spacing: spacing) }
					default: landing = nil
					}
				}
		} else {
			content
		}
	}
}
