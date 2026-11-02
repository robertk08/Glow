import SwiftData
import SwiftUI

struct LightTile: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	
	let fixture: Fixture
	let fixtures: [Fixture]
	let clashes: Bool
	
	@Binding var editing: Fixture?
	
	@State private var isRemoving = false
	@State private var origin = 0.0
	
	var body: some View {
		let mode = library.type(fixture.typeID)
		let programmer = Programmer(fixture: fixture, library: library, console: console)
		let isOn = programmer?.isOn ?? false
		let glow = programmer?.glow ?? .accentColor
		let isSelected = console.selection.contains(fixture)
		
		return VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				Image(systemName: clashes || programmer == nil ? "exclamationmark.triangle.fill" : fixture.symbol(mode))
					.font(.title3)
					.foregroundStyle(isOn || clashes || programmer == nil ? programmer?.displayInk ?? .white : .secondary)
					.frame(width: 38, height: 38)
					.background(clashes || programmer == nil ? Color.orange : isOn ? glow : Color(.tertiarySystemFill), in: .circle)
				
				Spacer()
			}
			
			VStack(alignment: .leading, spacing: 1) {
				Text(fixture.name)
					.font(.headline)
					.lineLimit(1)
				
				Text(clashes ? "Shares channels" : programmer?.address ?? "Needs a fixture")
					.font(.caption2)
					.foregroundStyle(clashes || programmer == nil ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
					.monospacedDigit()
					.lineLimit(1)
			}
			
			if let programmer, programmer.dims {
				Gauge(value: programmer.brightness) {
					Text(fixture.name)
				}
				.gaugeStyle(.accessoryLinearCapacity)
				.tint(isOn ? glow : Color(.tertiarySystemFill))
				.labelsHidden()
				.padding(.vertical, 6)
			}
		}
		.foregroundStyle(.primary)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.glassEffect(.regular.tint(isSelected ? Color.accentColor.opacity(0.35) : nil).interactive(), in: .rect(cornerRadius: 24, style: .continuous))
		.contentShape(.rect(cornerRadius: 24, style: .continuous))
		.gesture(SidewaysDrag {
			origin = programmer?.brightness ?? 0
		} moved: { distance in
			guard let programmer, programmer.dims else { return }
			programmer.brightness = origin + distance / 180
		})
		.onTapGesture {
			guard programmer != nil else {
				editing = fixture
				return
			}
			
			console.selection.toggle(fixture)
		}
		.contentShape(.dragPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isButton)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
		.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.contextMenu {
			Button(isOn ? "Turn Off" : "Turn On", systemImage: isOn ? "lightbulb.slash" : "lightbulb.max") {
				programmer?.toggleOn()
			}
			
			Button("Reset Light", systemImage: "arrow.uturn.backward") {
				programmer?.applyDefaults()
			}
			
			Divider()
			
			Button("Edit Light", systemImage: "slider.horizontal.3") {
				editing = fixture
			}
			
			Button("Duplicate", systemImage: "plus.square.on.square") {
				console.duplicate(fixture, among: fixtures, library: library, context: context)
			}
			
			Button("Remove Light", systemImage: "trash", role: .destructive) {
				isRemoving = true
			}
		}
		.confirmationDialog("Remove \(fixture.name)?", isPresented: $isRemoving, titleVisibility: .visible) {
			Button("Remove Light", role: .destructive) {
				context.delete(fixture)
			}
		} message: {
			Text("Its channels go back to zero and any scene holding it forgets it.")
		}
	}
}

private struct SidewaysDrag: UIGestureRecognizerRepresentable {
	let began: () -> Void
	let moved: (CGFloat) -> Void
	
	func makeUIGestureRecognizer(context: Context) -> Recognizer {
		Recognizer()
	}
	
	func handleUIGestureRecognizerAction(_ recognizer: Recognizer, context: Context) {
		switch recognizer.state {
		case .began:
			recognizer.setTranslation(.zero, in: recognizer.view)
			began()
		case .changed: moved(recognizer.translation(in: recognizer.view).x)
		default: break
		}
	}
	
	final class Recognizer: UIPanGestureRecognizer {
		private var start = CGPoint.zero
		
		override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
			super.touchesBegan(touches, with: event)
			start = touches.first?.location(in: view) ?? .zero
		}
		
		override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
			if state == .possible, let point = touches.first?.location(in: view) {
				let across = abs(point.x - start.x)
				let along = abs(point.y - start.y)
				
				if along > across, hypot(across, along) > 6 {
					state = .failed
					return
				}
			}
			
			super.touchesMoved(touches, with: event)
		}
	}
}
