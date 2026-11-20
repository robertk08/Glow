import SwiftData
import SwiftUI

enum Ordering {
	static func nextSortIndex<Item>(_ items: [Item], sortIndex: KeyPath<Item, Double>) -> Double {
		(items.map { $0[keyPath: sortIndex] }.max() ?? -1) + 1
	}
	
	static func sortIndex(between low: Double, and high: Double) -> Double? {
		let next = low + max(((high - low) * 128).rounded(.down), 1) / 256
		return next < high ? next : nil
	}
	
	@available(iOS 27.0, *)
	static func move<Item: PersistentModel>(_ difference: ReorderDifference<PersistentIdentifier, ReorderableSingleCollectionIdentifier>, among items: [Item], sortIndex: ReferenceWritableKeyPath<Item, Double>) {
		var destination = items.endIndex
		
		if case let .before(id) = difference.destination.position {
			destination = items.firstIndex { $0.persistentModelID == id } ?? items.endIndex
		}
		
		move(IndexSet(items.indices.filter { difference.sources.contains(items[$0].persistentModelID) }), to: destination, among: items, sortIndex: sortIndex)
	}
	
	static func move<Item: PersistentModel>(_ offsets: IndexSet, to destination: Int, among items: [Item], sortIndex: ReferenceWritableKeyPath<Item, Double>) {
		let lifted = offsets.map { items[$0] }
		guard !lifted.isEmpty else { return }
		var ordered = items
		ordered.remove(atOffsets: offsets)
		let position = min(max(destination - offsets.count { $0 < destination }, 0), ordered.count)
		
		var low = 0.0
		var step = 1.0
		
		if position > 0 {
			low = ordered[position - 1][keyPath: sortIndex]
		} else if position < ordered.count, ordered[position][keyPath: sortIndex] <= 0 {
			low = ordered[position][keyPath: sortIndex] - Double(lifted.count) - 1
		}
		
		if position < ordered.count, position > 0 || ordered[position][keyPath: sortIndex] > 0 {
			step = ((ordered[position][keyPath: sortIndex] - low) / Double(lifted.count + 1) * 256).rounded(.down) / 256
		}
		
		guard step > 0 else {
			ordered.insert(contentsOf: lifted, at: position)
			
			for (index, item) in ordered.enumerated() {
				item[keyPath: sortIndex] = Double(index)
			}
			return
		}
		
		for (offset, item) in lifted.enumerated() {
			item[keyPath: sortIndex] = low + step * Double(offset + 1)
		}
	}
}
