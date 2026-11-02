import SwiftUI

@Observable @MainActor
final class Arrangement {
	var frames: [String: CGRect] = [:]
	var geometry: ScrollGeometry?
	var width: CGFloat = 0
	var minimum: CGFloat = 168
	
	let spacing: CGFloat = 12
	
	private(set) var lifted: String?
	private(set) var finger = CGPoint.zero
	private(set) var isSettling = false
	private(set) var moves = 0
	private(set) var stretched: (scene: String, size: TileSize)?
	
	private var spots: [String: Int] = [:]
	private var resting: [String: Int] = [:]
	private var sizes: [String: TileSize] = [:]
	private var grab = CGSize.zero
	private var base = CGRect.zero
	
	var columns: Int {
		TileLayout.columns(in: width, minimum: minimum, spacing: spacing)
	}
	
	private var column: CGFloat {
		(width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
	}
	
	func slot(of look: Look) -> Int {
		guard lifted != nil || stretched != nil, let spot = spots[look.identifier] else { return look.slot }
		return spot
	}
	
	func size(of look: Look) -> TileSize {
		guard let stretched, stretched.scene == look.identifier else { return look.size }
		return stretched.size
	}
	
	func arranged(_ looks: [Look]) -> [Look] {
		looks.enumerated().sorted { (slot(of: $0.element), $0.offset) < (slot(of: $1.element), $1.offset) }.map(\.element)
	}
	
	func row(among looks: [Look]) -> CGFloat? {
		for look in looks {
			guard let frame = frames[look.identifier] else { continue }
			return (frame.height - spacing * CGFloat(size(of: look).rows - 1)) / CGFloat(size(of: look).rows)
		}
		
		return nil
	}
	
	private func origins(among looks: [Look]) -> [String: Int] {
		let arranged = arranged(looks)
		let origins = TileLayout.origins(of: arranged.map { size(of: $0) }, at: arranged.map { slot(of: $0) }, columns: columns)
		return Dictionary(zip(arranged.map(\.identifier), origins), uniquingKeysWith: { first, _ in first })
	}
	
	func outlines(among looks: [Look]) -> [CGRect] {
		guard let row = row(among: looks) else { return [] }
		let placed = origins(among: looks)
		var taken = Set<Int>()
		
		for look in looks {
			guard let origin = placed[look.identifier] else { continue }
			taken.formUnion(TileLayout.cells(of: size(of: look), at: origin, columns: columns))
		}
		
		let rows = (taken.max() ?? 0) / columns + 2
		return (0..<rows * columns).filter { !taken.contains($0) }.map { cell in
			CGRect(x: CGFloat(cell % columns) * (column + spacing), y: CGFloat(cell / columns) * (row + spacing), width: column, height: row)
		}
	}
	
	var landing: CGRect? {
		lifted.flatMap { frames[$0] }
	}
	
	var floating: CGRect? {
		guard let lifted, let frame = frames[lifted] else { return nil }
		return CGRect(origin: CGPoint(x: min(max(finger.x - grab.width, 0), max(width - frame.width, 0)), y: max(finger.y - grab.height, 0)), size: frame.size)
	}
	
	func lift(_ scene: String, at point: CGPoint, among looks: [Look]) {
		guard lifted == nil || isSettling, let frame = frames[scene] else { return }
		resting = origins(among: looks)
		spots = resting
		sizes = Dictionary(looks.map { ($0.identifier, $0.size) }, uniquingKeysWith: { first, _ in first })
		grab = CGSize(width: point.x - frame.minX, height: point.y - frame.minY)
		finger = point
		isSettling = false
		
		withAnimation(.snappy(duration: 0.3)) {
			lifted = scene
		}
	}
	
	func drag(to point: CGPoint) {
		finger = point
		guard let lifted, let size = sizes[lifted], let frame = frames[lifted] else { return }
		let taken = taken(besides: lifted)
		let row = (frame.height - spacing * CGFloat(size.rows - 1)) / CGFloat(size.rows)
		let across = min(size.columns, columns)
		let x = min(max(Int(((point.x - grab.width) / (column + spacing)).rounded()), 0), columns - across)
		let bottom = resting.compactMap { scene, origin in sizes[scene].flatMap { TileLayout.cells(of: $0, at: origin, columns: columns).max() } }.max() ?? 0
		let y = min(max(Int(((point.y - grab.height) / (row + spacing)).rounded()), 0), bottom / columns + 1)
		let placed = place(lifted, at: y * columns + x, size: size, taken: taken)
		guard placed != spots else { return }
		
		withAnimation(.snappy(duration: 0.3)) {
			spots = placed
		}
		moves += 1
	}
	
	private func place(_ scene: String, at destination: Int, size: TileSize, taken: [Int: String]) -> [String: Int] {
		let target = Set(TileLayout.cells(of: size, at: destination, columns: columns))
		let covered = Set(target.compactMap { taken[$0] })
		var filled = target
		var placed = resting
		placed[scene] = destination
		
		for (other, origin) in resting where other != scene && !covered.contains(other) {
			guard let size = sizes[other] else { continue }
			filled.formUnion(TileLayout.cells(of: size, at: origin, columns: columns))
		}
		
		for other in covered.sorted(by: { resting[$0, default: 0] < resting[$1, default: 0] }) {
			guard let size = sizes[other], var origin = resting[other] else { continue }
			
			while !filled.isDisjoint(with: TileLayout.cells(of: size, at: origin, columns: columns)) {
				origin += columns
			}
			
			placed[other] = origin
			filled.formUnion(TileLayout.cells(of: size, at: origin, columns: columns))
		}
		
		return placed
	}
	
	private func taken(besides scene: String) -> [Int: String] {
		var taken: [Int: String] = [:]
		
		for (other, origin) in resting where other != scene {
			guard let size = sizes[other] else { continue }
			
			for cell in TileLayout.cells(of: size, at: origin, columns: columns) {
				taken[cell] = other
			}
		}
		
		return taken
	}
	
	func stretch(_ scene: String, by translation: CGSize, among looks: [Look]) {
		guard lifted == nil, let look = looks.first(where: { $0.identifier == scene }), let frame = stretched == nil ? frames[scene] : base else { return }
		base = frame
		let row = (frame.height - spacing * CGFloat(look.size.rows - 1)) / CGFloat(look.size.rows)
		let across = frame.width + translation.width > column * 1.5 + spacing && columns > 1
		let down = frame.height + translation.height > row * 1.5 + spacing
		stretch(scene, to: down ? .large : across ? .wide : .small, among: looks)
	}
	
	func stretch(_ scene: String, to size: TileSize, among looks: [Look]) {
		guard lifted == nil else { return }
		
		if stretched == nil {
			resting = origins(among: looks)
			spots = resting
			sizes = Dictionary(looks.map { ($0.identifier, $0.size) }, uniquingKeysWith: { first, _ in first })
		}
		
		guard let start = resting[scene] else { return }
		let previous = stretched?.size
		guard previous != size else { return }
		var origin = start
		
		while origin % columns > 0, !TileLayout.fits(size, at: origin, columns: columns) {
			origin -= 1
		}
		
		let placed = place(scene, at: origin, size: size, taken: taken(besides: scene))
		
		withAnimation(.snappy(duration: 0.3)) {
			stretched = (scene, size)
			spots = placed
		}
		
		if previous != nil { moves += 1 }
	}
	
	func settle(among looks: [Look]) {
		guard let stretched else { return }
		
		withAnimation(.snappy(duration: 0.3)) {
			for look in looks {
				if look.identifier == stretched.scene, look.size != stretched.size { look.size = stretched.size }
				guard let spot = spots[look.identifier], Double(spot) != look.sortIndex else { continue }
				look.sortIndex = Double(spot)
			}
			
			self.stretched = nil
		}
	}
	
	func autoscroll() -> CGFloat? {
		guard lifted != nil, !isSettling, let geometry else { return nil }
		let edge: CGFloat = 72
		let top = geometry.visibleRect.minY + geometry.contentInsets.top + edge
		let bottom = geometry.visibleRect.maxY - geometry.contentInsets.bottom - edge
		var step: CGFloat = 0
		
		if finger.y < top {
			step = -min(edge, top - finger.y) / 6
		} else if finger.y > bottom {
			step = min(edge, finger.y - bottom) / 6
		}
		
		let lowest = -geometry.contentInsets.top
		let highest = max(lowest, geometry.contentSize.height - geometry.containerSize.height - geometry.contentInsets.top)
		let offset = min(max(geometry.contentOffset.y + step, lowest), highest)
		let moved = offset - geometry.contentOffset.y
		guard abs(moved) >= 0.5 else { return nil }
		self.geometry?.contentOffset.y = offset
		drag(to: CGPoint(x: finger.x, y: finger.y + moved))
		return offset + geometry.contentInsets.top
	}
	
	func drop(among looks: [Look]) {
		guard let lifted, let frame = frames[lifted] else {
			self.lifted = nil
			return
		}
		
		if spots != resting {
			for look in looks {
				guard let spot = spots[look.identifier], Double(spot) != look.sortIndex else { continue }
				look.sortIndex = Double(spot)
			}
		}
		
		isSettling = true
		
		withAnimation(.snappy(duration: 0.3)) {
			finger = CGPoint(x: frame.minX + grab.width, y: frame.minY + grab.height)
		} completion: {
			guard self.isSettling else { return }
			self.lifted = nil
			self.isSettling = false
		}
	}
}
