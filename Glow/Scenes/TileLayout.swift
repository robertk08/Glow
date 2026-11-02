import SwiftUI

nonisolated struct TileSpan: LayoutValueKey {
	static let defaultValue = TileSize.small
}

nonisolated struct TileSlot: LayoutValueKey {
	static let defaultValue = 0
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
	
	static func columns(in width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
		max(1, Int((width + spacing) / (minimum + spacing)))
	}
	
	static func cells(of size: TileSize, at origin: Int, columns: Int) -> [Int] {
		let across = min(size.columns, columns)
		return (0..<size.rows).flatMap { line in (0..<across).map { origin + line * columns + $0 } }
	}
	
	static func fits(_ size: TileSize, at origin: Int, columns: Int) -> Bool {
		origin >= 0 && origin % columns + min(size.columns, columns) <= columns
	}
	
	static func origins(of sizes: [TileSize], at slots: [Int], columns: Int) -> [Int] {
		var taken = Set<Int>()
		var origins: [Int] = []
		
		for (size, slot) in zip(sizes, slots) {
			var origin = max(slot, 0)
			
			while !fits(size, at: origin, columns: columns) || !taken.isDisjoint(with: cells(of: size, at: origin, columns: columns)) {
				origin += 1
			}
			
			taken.formUnion(cells(of: size, at: origin, columns: columns))
			origins.append(origin)
		}
		
		return origins
	}
	
	private func cells(of subviews: Subviews, width: CGFloat) -> [(index: Int, frame: CGRect)] {
		let columns = Self.columns(in: width, minimum: minimum, spacing: spacing)
		let column = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
		let sizes = subviews.map { $0[TileSpan.self] }
		let heights = zip(subviews, sizes).map { subview, size in
			let across = min(size.columns, columns)
			let width = column * CGFloat(across) + spacing * CGFloat(across - 1)
			return (size.rows, (subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height - spacing * CGFloat(size.rows - 1)) / CGFloat(size.rows))
		}
		let height = heights.filter { $0.0 == 1 }.map(\.1).max() ?? heights.map(\.1).max() ?? 0
		let origins = Self.origins(of: sizes, at: subviews.map { $0[TileSlot.self] }, columns: columns)
		var cells: [(index: Int, frame: CGRect)] = []
		
		for (index, size) in sizes.enumerated() {
			let across = min(size.columns, columns)
			let origin = origins[index]
			let frame = CGRect(x: CGFloat(origin % columns) * (column + spacing), y: CGFloat(origin / columns) * (height + spacing), width: column * CGFloat(across) + spacing * CGFloat(across - 1), height: height * CGFloat(size.rows) + spacing * CGFloat(size.rows - 1))
			cells.append((index, frame))
		}
		
		return cells
	}
}
