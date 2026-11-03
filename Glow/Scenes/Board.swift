import CoreGraphics

nonisolated struct Board: Equatable {
	let columns: Int
	private(set) var origins: [String: Int]
	private(set) var sizes: [String: TileSize]
	
	init(columns: Int, tiles: [(id: String, size: TileSize, slot: Int)]) {
		let ordered = tiles.enumerated().sorted { ($0.element.slot, $0.offset) < ($1.element.slot, $1.offset) }.map(\.element)
		let placed = TileLayout.origins(of: ordered.map(\.size), at: ordered.map(\.slot), columns: columns)
		self.columns = columns
		origins = Dictionary(zip(ordered.map(\.id), placed), uniquingKeysWith: { first, _ in first })
		sizes = Dictionary(tiles.map { ($0.id, $0.size) }, uniquingKeysWith: { first, _ in first })
	}
	
	@MainActor init(columns: Int, looks: [Look]) {
		self.init(columns: columns, tiles: looks.map { ($0.identifier, $0.size, $0.slot) })
	}
	
	var rows: Int {
		(origins.keys.compactMap { cells(of: $0).max() }.max() ?? -1) / columns + 1
	}
	
	func cells(of id: String) -> [Int] {
		guard let origin = origins[id], let size = sizes[id] else { return [] }
		return TileLayout.cells(of: size, at: origin, columns: columns)
	}
	
	func fitted(_ size: TileSize, at cell: Int) -> Int {
		let cell = max(cell, 0)
		return cell / columns * columns + min(cell % columns, columns - min(size.columns, columns))
	}
	
	func origin(of id: String, centeredAt point: CGPoint, cell: CGSize, spacing: CGFloat) -> Int? {
		guard let size = sizes[id] else { return nil }
		let across = CGFloat(min(size.columns, columns))
		let column = Int(((point.x - (across * cell.width + (across - 1) * spacing) / 2) / (cell.width + spacing)).rounded())
		let row = Int(((point.y - (CGFloat(size.rows) * cell.height + CGFloat(size.rows - 1) * spacing) / 2) / (cell.height + spacing)).rounded())
		return fitted(size, at: max(row, 0) * columns + min(max(column, 0), columns - 1))
	}
	
	mutating func place(_ id: String, at cell: Int) {
		guard let size = sizes[id] else { return }
		settle(id, at: fitted(size, at: cell))
	}
	
	mutating func resize(_ id: String, to size: TileSize) {
		guard let origin = origins[id] else { return }
		sizes[id] = size
		settle(id, at: fitted(size, at: origin))
	}
	
	@MainActor func write(to looks: [Look]) {
		for look in looks {
			if let size = sizes[look.identifier], size != look.size { look.size = size }
			guard let origin = origins[look.identifier], Double(origin) != look.sortIndex else { continue }
			look.sortIndex = Double(origin)
		}
	}
	
	private mutating func settle(_ id: String, at origin: Int) {
		origins[id] = origin
		var filled = Set(cells(of: id))
		let covered = origins.keys.filter { $0 != id && !filled.isDisjoint(with: cells(of: $0)) }
		
		for other in origins.keys where other != id && !covered.contains(other) {
			filled.formUnion(cells(of: other))
		}
		
		for other in covered.sorted(by: { (origins[$0] ?? 0, $0) < (origins[$1] ?? 0, $1) }) {
			while !filled.isDisjoint(with: cells(of: other)) {
				origins[other, default: 0] += columns
			}
			
			filled.formUnion(cells(of: other))
		}
	}
}
