import SwiftUI

struct CueProgress: View {
	@Environment(Console.self) private var console
	
	let cue: ShowContents.Cue
	
	var body: some View {
		let start = console.cueStarted.addingTimeInterval(cue.delay)
		
		ProgressView(timerInterval: start...start.addingTimeInterval(max(cue.fade, 0.05)), countsDown: false)
			.labelsHidden()
			.accessibilityLabel("Fade")
	}
}
