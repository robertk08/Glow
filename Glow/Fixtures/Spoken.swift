import Foundation

nonisolated enum Spoken {
	static func words(_ identifier: String) -> String {
		var text = ""
		
		for letter in identifier {
			if text.isEmpty {
				text += letter.uppercased()
			} else if letter.isUppercase || letter.isNumber {
				text += " \(letter.lowercased())"
			} else {
				text.append(letter)
			}
		}
		
		return text
	}
}
