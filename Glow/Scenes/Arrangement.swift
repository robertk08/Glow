import SwiftUI

@Observable @MainActor
final class Arrangement {
	var frames: [String: CGRect] = [:]
	var geometry: ScrollGeometry?
	
	private(set) var lifted: String?
	private(set) var finger = CGPoint.zero
	private(set) var isSettling = false
	private(set) var moves = 0
	
	private var order: [String] = []
	private var grab = CGSize.zero
	private var passed: String?
	
	func arranged(_ looks: [Look]) -> [Look] {
		guard lifted != nil else { return looks }
		return looks.sorted { (order.firstIndex(of: $0.identifier) ?? order.count) < (order.firstIndex(of: $1.identifier) ?? order.count) }
	}
	
	func lift(_ scene: String, at point: CGPoint, among looks: [Look]) {
		guard lifted == nil || isSettling, let frame = frames[scene] else { return }
		order = looks.map(\.identifier)
		grab = CGSize(width: point.x - frame.minX, height: point.y - frame.minY)
		finger = point
		passed = nil
		isSettling = false
		
		withAnimation(.snappy) {
			lifted = scene
		}
	}
	
	var floating: CGRect? {
		guard let lifted, let frame = frames[lifted] else { return nil }
		return CGRect(origin: CGPoint(x: finger.x - grab.width, y: finger.y - grab.height), size: frame.size)
	}
	
	func drag(to point: CGPoint) {
		finger = point
		guard let lifted, let from = order.firstIndex(of: lifted) else { return }
		let target = order.firstIndex { $0 != lifted && frames[$0]?.contains(point) == true }
		let bottom = order.compactMap { frames[$0]?.maxY }.max() ?? 0
		
		guard let target else {
			passed = nil
			
			if point.y > bottom, from != order.count - 1 {
				withAnimation(.snappy) {
					order.append(order.remove(at: from))
				}
				moves += 1
			}
			return
		}
		
		guard order[target] != passed else { return }
		passed = order[target]
		
		withAnimation(.snappy) {
			order.insert(order.remove(at: from), at: target)
		}
		moves += 1
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
	
	func drop(among looks: [Look], console: Console) {
		guard let lifted, let frame = frames[lifted] else {
			self.lifted = nil
			return
		}
		
		if let from = looks.firstIndex(where: { $0.identifier == lifted }), let to = order.firstIndex(of: lifted), from != to {
			console.move(IndexSet(integer: from), to: to > from ? to + 1 : to, among: looks, sortIndex: \.sortIndex)
		}
		
		isSettling = true
		
		withAnimation(.snappy) {
			finger = CGPoint(x: frame.minX + grab.width, y: frame.minY + grab.height)
		} completion: {
			guard self.isSettling else { return }
			self.lifted = nil
			self.isSettling = false
		}
	}
}
