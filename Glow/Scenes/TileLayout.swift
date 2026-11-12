import SwiftUI

nonisolated struct TileSpan: LayoutValueKey {
	static let defaultValue = TileSize.small
}

nonisolated struct TileSlot: LayoutValueKey {
	static let defaultValue = 0
}

struct TileLayout: Layout {
	let columns: Int
	let minimum: CGFloat
	let spacing: CGFloat
	
	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let width = proposal.width ?? minimum * CGFloat(columns) + spacing * CGFloat(columns - 1)
		let placed = cells(of: subviews, width: width)
		return CGSize(width: width, height: placed.map { $0.frame.maxY }.max() ?? 0)
	}
	
	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		for cell in cells(of: subviews, width: bounds.width) {
			subviews[cell.index].place(at: CGPoint(x: bounds.minX + cell.frame.minX, y: bounds.minY + cell.frame.minY), proposal: ProposedViewSize(cell.frame.size))
		}
	}
	
	static func cells(of size: TileSize, at origin: Int, columns: Int) -> [Int] {
		(0..<size.rows).flatMap { line in (0..<size.columns).map { origin + line * columns + $0 } }
	}
	
	static func origins(of sizes: [TileSize], at slots: [Int], columns: Int) -> [Int] {
		var taken = Set<Int>()
		var origins: [Int] = []
		
		for (size, slot) in zip(sizes, slots) {
			var origin = max(slot, 0)
			
			while origin % size.columns != 0 || !taken.isDisjoint(with: cells(of: size, at: origin, columns: 2)) {
				origin += 1
			}
			
			taken.formUnion(cells(of: size, at: origin, columns: 2))
			origins.append(origin)
		}
		
		return columns == 2 ? origins : spread(origins, sizes: sizes)
	}
	
	static func spread(_ slots: [Int], sizes: [TileSize]) -> [Int] {
		let tall = Set(zip(slots, sizes).filter { $0.1 == .large }.map { $0.0 / 2 })
		var halves: [Int: Int] = [:]
		var taken = Set<Int>()
		var half = 0
		
		for row in 0...((slots.max() ?? 0) / 2) where !tall.contains(row - 1) {
			while taken.contains(half) {
				half += 1
			}
			
			halves[row] = half
			taken.formUnion(tall.contains(row) ? [half, half + 2] : [half])
		}
		
		return slots.map { (halves[$0 / 2] ?? 0) * 2 + $0 % 2 }
	}
	
	static func gathered(_ origins: [Int], sizes: [TileSize]) -> [Int] {
		let tall = Set(zip(origins, sizes).filter { $0.1 == .large }.map { $0.0 / 2 })
		var rows: [Int: Int] = [:]
		var row = 0
		
		for half in 0...((origins.max() ?? 0) / 2) where !tall.contains(half - 2) {
			rows[half] = row
			row += tall.contains(half) ? 2 : 1
		}
		
		return origins.map { (rows[$0 / 2] ?? 0) * 2 + $0 % 2 }
	}
	
	private func cells(of subviews: Subviews, width: CGFloat) -> [(index: Int, frame: CGRect)] {
		let column = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
		let sizes = subviews.map { $0[TileSpan.self] }
		let heights = zip(subviews, sizes).map { subview, size in
			let width = column * CGFloat(size.columns) + spacing * CGFloat(size.columns - 1)
			return (size.rows, subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
		}
		let height = heights.filter { $0.0 == 1 }.map(\.1).max() ?? heights.map(\.1).max() ?? 0
		let origins = Self.origins(of: sizes, at: subviews.map { $0[TileSlot.self] }, columns: columns)
		var cells: [(index: Int, frame: CGRect)] = []
		
		for (index, size) in sizes.enumerated() {
			let origin = origins[index]
			let frame = CGRect(x: CGFloat(origin % columns) * (column + spacing), y: CGFloat(origin / columns) * (height + spacing), width: column * CGFloat(size.columns) + spacing * CGFloat(size.columns - 1), height: height * CGFloat(size.rows) + spacing * CGFloat(size.rows - 1))
			cells.append((index, frame))
		}
		
		return cells
	}
}
