import SwiftUI

struct GoboMark: View {
	let shape: GoboShape
	
	var size: CGFloat = 44
	var tint: Color = .white
	var angle: Angle = .zero
	var turns: Double?
	var backdrop = true
	var isSelected = false
	
	private var drawing: some View {
		Canvas { context, area in
			let side = min(area.width, area.height)
			let centre = CGPoint(x: area.width / 2, y: area.height / 2)
			let ink = GraphicsContext.Shading.color(tint)
			let line = StrokeStyle(lineWidth: side * 0.06, lineCap: .round)
			
			switch shape {
			case .dot, .smallDot, .largeDot:
				let radius = side * (shape == .smallDot ? 0.16 : shape == .largeDot ? 0.37 : 0.27)
				context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)), with: ink)
			case .ring:
				context.stroke(Path(ellipseIn: CGRect(x: centre.x - side * 0.26, y: centre.y - side * 0.26, width: side * 0.52, height: side * 0.52)), with: ink, style: line)
			case .rings:
				for radius in [side * 0.36, side * 0.302, side * 0.256] {
					context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)), with: ink, style: StrokeStyle(lineWidth: side * 0.035))
				}
			case .tunnel:
				let foot = centre.y + side * 0.42
				for radius in [side * 0.37, side * 0.26, side * 0.2, side * 0.13, side * 0.082, side * 0.048] {
					context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius, y: foot - radius * 2, width: radius * 2, height: radius * 2)), with: ink, style: StrokeStyle(lineWidth: side * 0.03))
				}
			case .petals:
				for step in 0..<8 {
					var petal = Path()
					petal.move(to: CGPoint(x: 0, y: -side * 0.36))
					petal.addQuadCurve(to: CGPoint(x: 0, y: -side * 0.08), control: CGPoint(x: side * 0.065, y: -side * 0.22))
					petal.addQuadCurve(to: CGPoint(x: 0, y: -side * 0.36), control: CGPoint(x: -side * 0.065, y: -side * 0.22))
					petal = petal.applying(.init(rotationAngle: Double(step) * .pi / 4))
					context.fill(petal.applying(.init(translationX: centre.x, y: centre.y)), with: ink)
				}
			case .fourPetals:
				for step in 0..<4 {
					var petal = Path()
					petal.move(to: CGPoint(x: 0, y: -side * 0.36))
					petal.addCurve(to: CGPoint(x: side * 0.072, y: -side * 0.12), control1: CGPoint(x: side * 0.082, y: -side * 0.29), control2: CGPoint(x: side * 0.095, y: -side * 0.18))
					petal.addQuadCurve(to: CGPoint(x: -side * 0.072, y: -side * 0.12), control: CGPoint(x: 0, y: -side * 0.055))
					petal.addCurve(to: CGPoint(x: 0, y: -side * 0.36), control1: CGPoint(x: -side * 0.095, y: -side * 0.18), control2: CGPoint(x: -side * 0.082, y: -side * 0.29))
					petal = petal.applying(.init(rotationAngle: Double(step) * .pi / 2))
					context.fill(petal.applying(.init(translationX: centre.x, y: centre.y)), with: ink)
				}
				context.fill(Path(ellipseIn: CGRect(x: centre.x - side * 0.045, y: centre.y - side * 0.045, width: side * 0.09, height: side * 0.09)), with: ink)
			case .speckle:
				var seed = 7.0
				for step in 0..<170 {
					seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
					let radius = side * 0.41 * ((Double(step) + seed / 233280) / 170).squareRoot()
					seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
					let turn = Double(step) * 2.39996 + (seed / 233280 - 0.5) * 2.4
					let spot = side * (step.isMultiple(of: 17) ? 0.028 : 0.016)
					context.fill(Path(ellipseIn: CGRect(x: centre.x + cos(turn) * radius - spot, y: centre.y + sin(turn) * radius - spot, width: spot * 2, height: spot * 2)), with: ink)
				}
			case .breakup:
				var seed = 31.0
				for step in 0..<34 {
					let radius = side * 0.22 * ((Double(step) + 0.5) / 34).squareRoot()
					let turn = Double(step) * 2.39996
					seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
					let lean = seed / 233280 * .pi
					seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
					let reach = side * (0.1 + seed / 233280 * 0.14)
					let middle = CGPoint(x: centre.x + cos(turn) * radius, y: centre.y + sin(turn) * radius)
					var stroke = Path()
					stroke.move(to: CGPoint(x: middle.x - cos(lean) * reach, y: middle.y - sin(lean) * reach))
					stroke.addLine(to: CGPoint(x: middle.x + cos(lean) * reach, y: middle.y + sin(lean) * reach))
					context.stroke(stroke, with: ink, style: StrokeStyle(lineWidth: side * 0.03, lineCap: .round))
				}
			case .cross:
				var bars = Path()
				for step in 0..<4 {
					var arm = Path()
					arm.addRect(CGRect(x: -side * 0.062, y: -side * 0.365, width: side * 0.035, height: side * 0.335))
					arm.addRect(CGRect(x: side * 0.022, y: -side * 0.29, width: side * 0.035, height: side * 0.26))
					bars.addPath(arm.applying(.init(rotationAngle: Double(step) * .pi / 2)))
				}
				context.fill(bars.applying(.init(translationX: centre.x, y: centre.y)), with: ink)
			case .diagonalCross:
				var bars = Path()
				for step in 0..<2 {
					let arm = Path(CGRect(x: -side * 0.38, y: -side * 0.048, width: side * 0.76, height: side * 0.096))
					bars.addPath(arm.applying(.init(rotationAngle: Double(step) * .pi / 2 + .pi / 4)))
				}
				context.fill(bars.applying(.init(translationX: centre.x, y: centre.y)), with: ink)
			case .star:
				let tip = side * 0.38
				let dip = side * 0.03
				var points = Path()
				for step in 0..<4 {
					let turn = Double(step) * .pi / 2 + .pi / 4
					let ahead = turn + .pi / 2
					if step == 0 {
						points.move(to: CGPoint(x: cos(turn) * tip, y: sin(turn) * tip))
					}
					points.addQuadCurve(to: CGPoint(x: cos(ahead) * tip, y: sin(ahead) * tip), control: CGPoint(x: cos(turn + .pi / 4) * dip, y: sin(turn + .pi / 4) * dip))
				}
				points.closeSubpath()
				points.addRect(CGRect(x: -side * 0.075, y: -side * 0.075, width: side * 0.15, height: side * 0.15))
				context.fill(points.applying(.init(translationX: centre.x, y: centre.y)), with: ink, style: FillStyle(eoFill: true))
			case .starburst:
				var spikes = Path()
				for step in 0..<24 {
					let radius = side * (step.isMultiple(of: 2) ? 0.36 : 0.18)
					let turn = Double(step) * .pi / 12 - .pi / 2
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
				let reach = side * 0.36
				var edges = Path()
				edges.move(to: CGPoint(x: 0, y: reach))
				edges.addLine(to: CGPoint(x: -reach * 0.866, y: -reach * 0.5))
				edges.addLine(to: CGPoint(x: reach * 0.866, y: -reach * 0.5))
				edges.closeSubpath()
				context.stroke(edges.applying(CGAffineTransform(translationX: centre.x, y: centre.y).rotated(by: 0.16)), with: ink, style: StrokeStyle(lineWidth: side * 0.05))
			case .grid:
				let cell = side * 0.152
				let pitch = side * 0.186
				var panes = Path()
				for row in 0..<3 {
					for column in 0..<3 {
						panes.addRect(CGRect(x: (Double(column) - 1) * pitch - cell / 2, y: (Double(row) - 1) * pitch - cell / 2, width: cell, height: cell))
					}
				}
				context.fill(panes.applying(CGAffineTransform(translationX: centre.x, y: centre.y).rotated(by: 0.4)), with: ink)
			case .dashes:
				var marks = Path()
				for step in 0..<4 {
					for spot in [CGPoint(x: -side * 0.039, y: -side * 0.264), CGPoint(x: -side * 0.098, y: -side * 0.133)] {
						var bar = Path()
						bar.move(to: CGPoint(x: spot.x - side * 0.088, y: spot.y - side * 0.049))
						bar.addLine(to: CGPoint(x: spot.x + side * 0.088, y: spot.y + side * 0.049))
						marks.addPath(bar.applying(.init(rotationAngle: Double(step) * .pi / 2)))
					}
				}
				context.stroke(marks.applying(.init(translationX: centre.x, y: centre.y)), with: ink, style: StrokeStyle(lineWidth: side * 0.045))
			case .dotLine:
				for step in 0..<8 {
					let spot = side * 0.045
					let y = centre.y + (Double(step) - 3.5) * side * 0.105
					context.fill(Path(ellipseIn: CGRect(x: centre.x - spot, y: y - spot, width: spot * 2, height: spot * 2)), with: ink)
				}
			case .dotRing:
				for step in 0..<12 {
					let turn = Double(step) * .pi / 6 + .pi / 12
					let spot = side * 0.045
					context.fill(Path(ellipseIn: CGRect(x: centre.x + cos(turn) * side * 0.335 - spot, y: centre.y + sin(turn) * side * 0.335 - spot, width: spot * 2, height: spot * 2)), with: ink)
				}
			}
		}
	}
	
	var body: some View {
		Circle()
			.fill(backdrop ? Color(white: 0.12) : .clear)
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
					.strokeBorder(isSelected ? AnyShapeStyle(.tint) : backdrop ? AnyShapeStyle(.separator) : AnyShapeStyle(.clear), lineWidth: isSelected ? 3 : 1)
			}
			.frame(width: size, height: size)
	}
}
