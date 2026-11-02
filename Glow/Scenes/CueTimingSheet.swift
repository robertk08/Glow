import SwiftUI

struct CueTimingSheet: View {
	@Environment(Console.self) private var console
	@Environment(\.dismiss) private var dismiss
	
	let picked: [Cue]
	
	let start: CueDraft
	
	@State private var draft: CueDraft
	
	init(picked: [Cue]) {
		self.picked = picked
		let fades = Set(picked.map(\.fade))
		let delays = Set(picked.map(\.delay))
		let follows = Set(picked.map(\.follow))
		let first = CueDraft(fade: fades.count == 1 ? fades.first ?? 0 : -1, delay: delays.count == 1 ? delays.first ?? 0 : -1, follow: follows.count == 1 ? follows.first ?? nil : -1)
		start = first
		_draft = State(initialValue: first)
	}
	
	var body: some View {
		NavigationStack {
			Form {
				Section {
					CueTiming(fade: $draft.fade, delay: $draft.delay, follow: $draft.follow)
				}
			}
			.navigationTitle(picked.count == 1 ? "1 Cue" : "\(picked.count) Cues")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .close) {
						dismiss()
					}
				}
				
				ToolbarItem(placement: .confirmationAction) {
					Button(role: .confirm) {
						console.retime(picked, from: start, to: draft)
						dismiss()
					}
					.disabled(draft == start)
				}
			}
		}
		.presentationDetents([.medium, .large])
	}
}
