import SwiftUI

struct CueTiming: View {
	@Binding var fade: Double
	@Binding var delay: Double
	@Binding var follow: Double?
	
	var body: some View {
		if fade >= 0, delay >= 0, follow.map({ $0 >= 0 }) ?? true {
			CueTimeline(delay: delay, fade: fade, follow: follow, height: 18)
				.font(.subheadline.weight(.medium))
				.foregroundStyle(.tint)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 6)
				.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
				.animation(.snappy(duration: 0.25), value: [delay, fade, follow ?? -1])
		}
		
		SecondsField(title: CueTime.fade.name, symbol: CueTime.fade.symbol, seconds: $fade)
		
		SecondsField(title: CueTime.delay.name, symbol: CueTime.delay.symbol, seconds: $delay)
		
		Picker(selection: Binding { follow == nil ? false : follow.map { $0 < 0 } == true ? nil : true } set: { follow = $0 == true ? 0 : nil }.animation(.snappy(duration: 0.25))) {
			Text("On Go")
				.tag(Optional(false))
			
			Text("By Itself")
				.tag(Optional(true))
		} label: {
			Label(CueTime.follow.name, systemImage: CueTime.follow.symbol)
		}
		
		if let after = follow, after >= 0 {
			SecondsField(title: "After", symbol: "timer", seconds: Binding { after } set: { follow = $0 })
		}
	}
}
