import Foundation

nonisolated enum Identifier {
	static func fresh() -> String {
		var text = ""
		
		for _ in 0..<8 {
			text += String(format: "%02x", UInt8.random(in: .min ... .max))
		}
		
		return text
	}
	
	static func unusedName(_ base: String, among names: [String]) -> String {
		let taken = Set(names)
		guard taken.contains(base) else { return base }
		var index = 2
		
		while taken.contains("\(base) \(index)") {
			index += 1
		}
		
		return "\(base) \(index)"
	}
}
