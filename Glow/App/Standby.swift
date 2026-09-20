import SwiftUI

enum Standby: Equatable {
	case starting
	case welcome
	case searching
	case opening
	case ready
	
	var isBlank: Bool {
		switch self {
		case .starting, .ready: true
		case .welcome, .searching, .opening: false
		}
	}
	
	var offersSetup: Bool {
		switch self {
		case .welcome, .searching: true
		case .starting, .opening, .ready: false
		}
	}
	
	var showsLink: Bool {
		switch self {
		case .searching, .opening: true
		case .starting, .welcome, .ready: false
		}
	}
}
