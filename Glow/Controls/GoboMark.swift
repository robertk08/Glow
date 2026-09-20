import SwiftUI

struct GoboMark: View {
	let shape: GoboShape

	var size: CGFloat = 44
	var tint: Color = .white
	var angle: Angle = .zero
	var turns: Double?
	var isSelected = false

	private var drawing: some View {
		Canvas { context, area in
			let side = min(area.width, area.height)
			let centre = CGPoint(x: area.width / 2, y: area.height / 2)
			let ink = GraphicsContext.Shading.color(tint)
			let line = StrokeStyle(lineWidth: side * 0.06, lineCap: .round)

			switch shape {
			case .dot, .smallDot, .largeDot:
				let radius = side * (shape == .smallDot ? 0.12 : shape == .largeDot ? 0.32 : 0.21)
				context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)), with: ink)
			case .ring:
				context.stroke(Path(ellipseIn: CGRect(x: centre.x - side * 0.26, y: centre.y - side * 0.26, width: side * 0.52, height: side * 0.52)), with: ink, style: line)
			case .rings:
				for step in 1...3 {
					let radius = side * 0.12 * Double(step)
					context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)), with: ink, style: StrokeStyle(lineWidth: side * 0.05))
				}
			case .tunnel:
				for step in 0..<5 {
					let radius = side * (0.34 - Double(step) * 0.065)
					let drop = side * Double(step) * 0.05
					context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius + drop, width: radius * 2, height: radius * 2)), with: ink, style: StrokeStyle(lineWidth: side * 0.04))
				}
			case .petals, .fourPetals:
				let count = shape == .petals ? 8 : 4
				for step in 0..<count {
					var petal = Path(ellipseIn: CGRect(x: -side * 0.055, y: -side * 0.34, width: side * 0.11, height: side * 0.26))
					petal = petal.applying(.init(rotationAngle: Double(step) * 2 * .pi / Double(count)))
					context.fill(petal.applying(.init(translationX: centre.x, y: centre.y)), with: ink)
				}
			case .speckle:
				var seed = 7.0
				for _ in 0..<70 {
					seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
					let radius = side * 0.36 * (seed / 233280).squareRoot()
					seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
					let turn = seed / 233280 * 2 * .pi
					let spot = side * 0.022
					context.fill(Path(ellipseIn: CGRect(x: centre.x + cos(turn) * radius - spot, y: centre.y + sin(turn) * radius - spot, width: spot * 2, height: spot * 2)), with: ink)
				}
			case .breakup:
				var seed = 31.0
				for _ in 0..<16 {
					seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
					let radius = side * 0.3 * (seed / 233280)
					seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
					let turn = seed / 233280 * 2 * .pi
					seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
					let lean = seed / 233280 * 2 * .pi
					let start = CGPoint(x: centre.x + cos(turn) * radius, y: centre.y + sin(turn) * radius)
					var stroke = Path()
					stroke.move(to: start)
					stroke.addLine(to: CGPoint(x: start.x + cos(lean) * side * 0.18, y: start.y + sin(lean) * side * 0.18))
					context.stroke(stroke, with: ink, style: StrokeStyle(lineWidth: side * 0.035, lineCap: .round))
				}
			case .cross, .diagonalCross:
				var bars = Path()
				bars.addRoundedRect(in: CGRect(x: centre.x - side * 0.05, y: centre.y - side * 0.34, width: side * 0.1, height: side * 0.68), cornerSize: CGSize(width: side * 0.03, height: side * 0.03))
				bars.addRoundedRect(in: CGRect(x: centre.x - side * 0.34, y: centre.y - side * 0.05, width: side * 0.68, height: side * 0.1), cornerSize: CGSize(width: side * 0.03, height: side * 0.03))
				guard shape == .cross else {
					let turn = CGAffineTransform(translationX: centre.x, y: centre.y).rotated(by: .pi / 4).translatedBy(x: -centre.x, y: -centre.y)
					context.fill(bars.applying(turn), with: ink)
					break
				}
				context.fill(bars, with: ink)
			case .star, .starburst:
				let points = shape == .star ? 4 : 12
				let inner = shape == .star ? 0.12 : 0.2
				var spikes = Path()
				for step in 0..<(points * 2) {
					let radius = side * (step.isMultiple(of: 2) ? 0.36 : inner)
					let turn = Double(step) * .pi / Double(points) - .pi / 2
					let place = CGPoint(x: centre.x + cos(turn) * radius, y: centre.y + sin(turn) * radius)
					if step == 0 {
						spikes.move(to: place)
					} else {
						spikes.addLine(to: place)
					}
				}
				spikes.closeSubpath()
				context.fill(spikes, with: ink)
			case .triangle:
				var edges = Path()
				edges.move(to: CGPoint(x: centre.x - side * 0.32, y: centre.y - side * 0.24))
				edges.addLine(to: CGPoint(x: centre.x + side * 0.32, y: centre.y - side * 0.24))
				edges.addLine(to: CGPoint(x: centre.x, y: centre.y + side * 0.32))
				edges.closeSubpath()
				context.stroke(edges, with: ink, style: line)
			case .grid:
				let cell = side * 0.17
				let gap = side * 0.04
				let origin = centre.x - cell * 1.5 - gap
				for row in 0..<3 {
					for column in 0..<3 {
						let box = CGRect(x: origin + Double(column) * (cell + gap), y: centre.y - cell * 1.5 - gap + Double(row) * (cell + gap), width: cell, height: cell)
						context.fill(Path(box), with: ink)
					}
				}
			case .dashes:
				for step in 0..<6 {
					let row = Double(step % 3)
					let column = Double(step / 3)
					var dash = Path()
					let y = centre.y + (row - 1) * side * 0.18
					let x = centre.x + (column - 0.5) * side * 0.3
					dash.move(to: CGPoint(x: x - side * 0.1, y: y))
					dash.addLine(to: CGPoint(x: x + side * 0.1, y: y))
					context.stroke(dash, with: ink, style: StrokeStyle(lineWidth: side * 0.05, lineCap: .round))
				}
			case .dotLine:
				for step in 0..<7 {
					let spot = side * 0.035
					let y = centre.y + (Double(step) - 3) * side * 0.1
					context.fill(Path(ellipseIn: CGRect(x: centre.x - spot, y: y - spot, width: spot * 2, height: spot * 2)), with: ink)
				}
			case .dotRing:
				for step in 0..<12 {
					let turn = Double(step) * .pi / 6
					let spot = side * 0.035
					context.fill(Path(ellipseIn: CGRect(x: centre.x + cos(turn) * side * 0.28 - spot, y: centre.y + sin(turn) * side * 0.28 - spot, width: spot * 2, height: spot * 2)), with: ink)
				}
			}
		}
	}

	var body: some View {
		Circle()
			.fill(Color(white: 0.12))
			.overlay {
				if let turns {
					TimelineView(.animation) { timeline in
						drawing
							.rotationEffect(.degrees(timeline.date.timeIntervalSinceReferenceDate * turns * 6))
					}
				} else {
					drawing
						.rotationEffect(angle)
				}
			}
			.overlay {
				Circle()
					.strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: isSelected ? 3 : 1)
			}
			.frame(width: size, height: size)
	}
}
