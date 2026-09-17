import Testing

@testable import Glow

struct ColourTests {
	@Test func subtractiveMixingInvertsTheTarget() {
		let mix = EmitterMix.mixing(LightColor(red: 0, green: 0.28, blue: 1), emitters: Emitter.flags, mixing: .subtractive)
		
		#expect(abs(mix[.cyan] - 1) < 0.0001)
		#expect(abs(mix[.magenta] - 0.72) < 0.0001)
		#expect(abs(mix[.yellow]) < 0.0001)
	}
	
	@Test func subtractiveMixingReadsBackWhatItWasGiven() {
		let target = LightColor(red: 0.2, green: 0.6, blue: 1)
		let read = EmitterMix.mixing(target, emitters: Emitter.flags, mixing: .subtractive).light(.subtractive)
		
		#expect(abs(read.red - target.red) < 0.0001)
		#expect(abs(read.green - target.green) < 0.0001)
		#expect(abs(read.blue - target.blue) < 0.0001)
	}
	
	@Test func flagsOutOfTheBeamIsWhite() {
		let light = EmitterMix([.cyan: 0, .magenta: 0, .yellow: 0]).light(.subtractive)
		
		#expect(light.red == 1)
		#expect(light.green == 1)
		#expect(light.blue == 1)
	}
	
	@Test func flagsFullyInIsBlack() {
		let light = EmitterMix([.cyan: 1, .magenta: 1, .yellow: 1]).light(.subtractive)
		
		#expect(light.red == 0)
		#expect(light.green == 0)
		#expect(light.blue == 0)
	}
	
	@Test func additiveMixingReachesRedOnTheRedEmitterAlone() {
		let mix = EmitterMix.mixing(LightColor(red: 1, green: 0, blue: 0), emitters: [.red, .green, .blue], mixing: .additive)
		
		#expect(mix[.red] == 1)
		#expect(mix[.green] == 0)
		#expect(mix[.blue] == 0)
	}
	
	@Test func additiveMixingPrefersTheWhiteEmitterForWhite() {
		let mix = EmitterMix.mixing(LightColor(red: 1, green: 1, blue: 1), emitters: [.white, .red, .green, .blue], mixing: .additive)
		
		#expect(mix[.white] == 1)
	}
	
	@Test func ultravioletIsNeverMixedIntoAColour() {
		let mix = EmitterMix.mixing(LightColor(red: 0.3, green: 0, blue: 0.9), emitters: [.red, .green, .blue, .uv], mixing: .additive)
		
		#expect(mix[.uv] == 0)
	}
	
	@Test func aWhitePointIsRecognisedFromTheColourItMakes() {
		let found = ColorTemperature.nearest(to: ColorTemperature.light(kelvin: 3000))
		
		#expect(found != nil)
		#expect(abs((found ?? 0) - 3000) <= 50)
	}
	
	@Test func aSaturatedColourHasNoWhitePoint() {
		#expect(ColorTemperature.nearest(to: LightColor(red: 0, green: 1, blue: 0)) == nil)
	}
	
	@Test func normalisingRaisesThePeakToFull() {
		let light = LightColor(red: 0.2, green: 0.4, blue: 0.1).normalised
		
		#expect(abs(light.green - 1) < 0.0001)
		#expect(abs(light.red - 0.5) < 0.0001)
	}
}
