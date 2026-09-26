import SwiftUI

enum Standby: Equatable {
	case starting
	case welcome
	case searching
	case locked
	case ready
	
	var isBlank: Bool {
		switch self {
		case .starting, .ready: true
		case .welcome, .searching, .locked: false
		}
	}
	
	var offersSetup: Bool {
		switch self {
		case .welcome, .searching: true
		case .starting, .locked, .ready: false
		}
	}
	
	var showsLink: Bool {
		switch self {
		case .searching: true
		case .starting, .welcome, .locked, .ready: false
		}
	}
}
