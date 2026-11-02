import SwiftUI

struct CueTiming: View {
	@Binding var fade: Double
	@Binding var delay: Double
	@Binding var follow: Double?
	
	var body: some View {
		CueTimeline(delay: delay, fade: fade, follow: follow, height: 14)
			.font(.footnote)
			.foregroundStyle(.tint)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 6)
			.animation(.snappy(duration: 0.25), value: [delay, fade, follow ?? -1])
		
		SecondsField(title: CueTime.fade.name, symbol: CueTime.fade.symbol, seconds: $fade)
		
		SecondsField(title: CueTime.delay.name, symbol: CueTime.delay.symbol, seconds: $delay)
		
		Picker(selection: Binding { follow != nil } set: { follow = $0 ? 0 : nil }.animation(.snappy(duration: 0.25))) {
			Text("On Go")
				.tag(false)
			
			Text("By Itself")
				.tag(true)
		} label: {
			Label(CueTime.follow.name, systemImage: CueTime.follow.symbol)
		}
		
		if follow != nil {
			SecondsField(title: "After", symbol: "timer", seconds: Binding { follow ?? 0 } set: { follow = $0 })
		}
	}
}
