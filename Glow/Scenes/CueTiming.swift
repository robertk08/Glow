import SwiftUI

struct CueTiming: View {
	@Binding var fade: Double
	@Binding var delay: Double
	@Binding var follow: Double?
	
	var body: some View {
		SecondsField(title: CueTime.fade.name, symbol: CueTime.fade.symbol, seconds: $fade)
		
		SecondsField(title: CueTime.delay.name, symbol: CueTime.delay.symbol, seconds: $delay)
		
		Toggle(isOn: Binding { follow != nil } set: { follow = $0 ? 0 : nil }.animation()) {
			Label(CueTime.follow.name, systemImage: CueTime.follow.symbol)
		}
		
		if follow != nil {
			SecondsField(title: "After", symbol: "timer", seconds: Binding { follow ?? 0 } set: { follow = $0 })
		}
	}
}
