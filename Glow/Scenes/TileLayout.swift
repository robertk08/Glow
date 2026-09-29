import SwiftUI

nonisolated struct TileSpan: LayoutValueKey {
	static let defaultValue = TileSize.small
}

struct TileLayout: Layout {
	let minimum: CGFloat
	let spacing: CGFloat
	
	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let width = proposal.width ?? minimum * 2 + spacing
		let placed = cells(of: subviews, width: width)
		return CGSize(width: width, height: placed.map { $0.frame.maxY }.max() ?? 0)
	}
	
	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		for cell in cells(of: subviews, width: bounds.width) {
			subviews[cell.index].place(at: CGPoint(x: bounds.minX + cell.frame.minX, y: bounds.minY + cell.frame.minY), proposal: ProposedViewSize(cell.frame.size))
		}
	}
	
	private func cells(of subviews: Subviews, width: CGFloat) -> [(index: Int, frame: CGRect)] {
		let columns = max(1, Int((width + spacing) / (minimum + spacing)))
		let column = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
		let spans = subviews.map { (across: min($0[TileSpan.self].columns, columns), down: $0[TileSpan.self].rows) }
		let height = zip(subviews, spans).map { subview, span in
			let width = column * CGFloat(span.across) + spacing * CGFloat(span.across - 1)
			return (subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height - spacing * CGFloat(span.down - 1)) / CGFloat(span.down)
		}.max() ?? 0
		var taken = Set<Int>()
		var cells: [(index: Int, frame: CGRect)] = []
		
		for (index, span) in spans.enumerated() {
			var slot = 0
			
			while slot % columns + span.across > columns || (0..<span.down).contains(where: { line in (0..<span.across).contains { taken.contains(slot + line * columns + $0) } }) {
				slot += 1
			}
			
			for line in 0..<span.down {
				for place in 0..<span.across {
					taken.insert(slot + line * columns + place)
				}
			}
			
			let frame = CGRect(x: CGFloat(slot % columns) * (column + spacing), y: CGFloat(slot / columns) * (height + spacing), width: column * CGFloat(span.across) + spacing * CGFloat(span.across - 1), height: height * CGFloat(span.down) + spacing * CGFloat(span.down - 1))
			cells.append((index, frame))
		}
		
		return cells
	}
}
