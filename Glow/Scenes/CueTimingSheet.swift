import SwiftUI

struct CueTimingSheet: View {
	@Environment(Console.self) private var console
	@Environment(\.dismiss) private var dismiss
	
	let picked: [Cue]
	
	let start: CueDraft
	
	@State private var draft: CueDraft
	
	init(picked: [Cue]) {
		self.picked = picked
		let first = CueDraft(fade: picked.first?.fade ?? 0, delay: picked.first?.delay ?? 0, follow: picked.first?.follow)
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
