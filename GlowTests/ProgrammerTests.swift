import Foundation
import SwiftUI
import Testing

@testable import Glow

@MainActor
struct ProgrammerTests {
	private func rig(_ channels: [FixtureChannel], mixing: ColorMixing = .additive) -> (Console, Programmer) {
		let type = FixtureType(id: "t", model: "T", mixing: mixing, channels: channels)
		let console = Console()
		let programmer = Programmer(type: type, start: DMXAddress(1)!, console: console)
		programmer.applyDefaults()
		return (console, programmer)
	}
	
	private var rgbwWithDimmer: [FixtureChannel] {
		[
			FixtureChannel(offset: 1, attribute: .dimmer),
			FixtureChannel(offset: 2, attribute: .red),
			FixtureChannel(offset: 3, attribute: .green),
			FixtureChannel(offset: 4, attribute: .blue),
			FixtureChannel(offset: 5, attribute: .white, defaultValue: 255),
			FixtureChannel(offset: 6, attribute: .pan, defaultValue: 128),
			FixtureChannel(offset: 7, attribute: .tilt, defaultValue: 128),
		]
	}
	
	@Test func defaultsPutTheLightAtWhiteAndCentredWithoutTurningItOn() {
		let (console, programmer) = rig(rgbwWithDimmer)
		
		#expect(programmer.brightness == 0)
		#expect(console.value(at: DMXAddress(5)!) == 255)
		#expect(console.value(at: DMXAddress(6)!) == 128)
		#expect(console.value(at: DMXAddress(7)!) == 128)
	}
	
	@Test func nothingIsActiveUntilYouSetIt() {
		let (_, programmer) = rig(rgbwWithDimmer)
		
		for channel in programmer.channels {
			#expect(!programmer.isActive(channel), "\(channel.attribute) should start unset")
		}
	}
	
	@Test func raisingTheDimmerDoesNotStampColourOrPosition() {
		let (console, programmer) = rig(rgbwWithDimmer)
		programmer.brightness = 1
		
		#expect(programmer.isActive(.dimmer))
		#expect(!programmer.isActive(.color))
		#expect(!programmer.isActive(.position))
		#expect(console.value(at: DMXAddress(1)!) == 255)
		#expect(console.value(at: DMXAddress(5)!) == 255)
		#expect(programmer.light.red > 0.9 && programmer.light.green > 0.9 && programmer.light.blue > 0.9)
	}
	
	@Test func settingAColourMarksOnlyColourActive() {
		let (_, programmer) = rig(rgbwWithDimmer)
		programmer.apply(LightColor(red: 1, green: 0, blue: 0))
		
		#expect(programmer.isActive(.color))
		#expect(!programmer.isActive(.dimmer))
		#expect(!programmer.isActive(.position))
	}
	
	@Test func releasingPutsEverythingBackToDefaultedAndUnset() {
		let (console, programmer) = rig(rgbwWithDimmer)
		programmer.brightness = 1
		programmer.apply(LightColor(red: 1, green: 0, blue: 0))
		programmer.applyDefaults()
		
		#expect(programmer.brightness == 0)
		#expect(console.value(at: DMXAddress(5)!) == 255)
		#expect(!programmer.isActive(.color))
		#expect(!programmer.isActive(.dimmer))
	}
	
	@Test func aDimBandCarriesBrightnessBothWays() {
		var shutter = FixtureChannel(offset: 1, attribute: .shutter)
		shutter.functions = [
			ChannelFunction(from: 0, to: 9, label: "Closed", purpose: .closed),
			ChannelFunction(from: 10, to: 210, label: "Dimmer", kind: .proportional, purpose: .dim),
			ChannelFunction(from: 211, to: 255, label: "Strobe", kind: .proportional),
		]
		let (console, programmer) = rig([shutter])
		
		programmer.brightness = 1
		#expect(console.value(at: DMXAddress(1)!) == 210)
		#expect(abs(programmer.brightness - 1) < 0.0001)
		
		programmer.brightness = 0.5
		#expect(console.value(at: DMXAddress(1)!) == 110)
		
		programmer.brightness = 0
		#expect(console.value(at: DMXAddress(1)!) == 0)
		#expect(!programmer.isOn)
	}
	
	@Test func sixteenBitChannelsMoveTogether() {
		let (console, programmer) = rig([FixtureChannel(offset: 1, attribute: .pan, fineOffset: 2)])
		
		programmer.setFraction(1, for: .pan)
		#expect(console.value(at: DMXAddress(1)!) == 255)
		#expect(console.value(at: DMXAddress(2)!) == 255)
		
		programmer.setFraction(0.5, for: .pan)
		#expect(abs(programmer.fraction(.pan) - 0.5) < 0.0001)
	}
	
	@Test func aSubtractiveHeadTakesColourWithoutTouchingItsDimmer() {
		let (console, programmer) = rig([
			FixtureChannel(offset: 1, attribute: .dimmer, defaultValue: 255),
			FixtureChannel(offset: 2, attribute: .cyan),
			FixtureChannel(offset: 3, attribute: .magenta),
			FixtureChannel(offset: 4, attribute: .yellow),
		], mixing: .subtractive)
		
		#expect(abs(programmer.brightness - 1) < 0.005)
		
		programmer.apply(LightColor(red: 0, green: 0, blue: 1))
		#expect(console.value(at: DMXAddress(2)!) == 255)
		#expect(console.value(at: DMXAddress(3)!) == 255)
		#expect(console.value(at: DMXAddress(4)!) == 0)
		#expect(abs(programmer.brightness - 1) < 0.005)
	}
	
	@Test func highlightOpensTheFixtureWithoutSettingAnything() {
		var shutter = FixtureChannel(offset: 2, attribute: .shutter)
		shutter.functions = [ChannelFunction(from: 0, to: 7, label: "Closed", purpose: .closed), ChannelFunction(from: 240, to: 255, label: "Open", purpose: .open)]
		let (console, programmer) = rig([FixtureChannel(offset: 1, attribute: .dimmer), shutter])
		
		programmer.highlight()
		
		#expect(console.value(at: DMXAddress(1)!) == 255)
		#expect(console.value(at: DMXAddress(2)!) == 240)
		#expect(!programmer.isActive(.dimmer))
	}
	
	@Test func aSliderStepsOverASettingThatHasToBeConfirmed() {
		var reset = FixtureChannel(offset: 1, attribute: .reset)
		var danger = ChannelFunction(from: 150, to: 200, label: "Reset head")
		danger.requiresConfirmation = true
		reset.functions = [ChannelFunction(from: 0, to: 149, label: "No function"), danger, ChannelFunction(from: 201, to: 255, label: "No function")]
		let (console, programmer) = rig([reset])
		
		programmer.guardedBinding(reset).wrappedValue = 175
		
		#expect(console.value(at: DMXAddress(1)!) == 149)
	}
	
	@Test func aMacroThatOverridesTheMixerSaysSo() {
		var macro = FixtureChannel(offset: 5, attribute: .colorMacro)
		macro.functions = [ChannelFunction(from: 0, to: 7, label: "Mixer", purpose: .release), ChannelFunction(from: 8, to: 255, label: "Built-in color", kind: .proportional)]
		let (_, programmer) = rig([
			FixtureChannel(offset: 1, attribute: .dimmer),
			FixtureChannel(offset: 2, attribute: .red),
			FixtureChannel(offset: 3, attribute: .green),
			FixtureChannel(offset: 4, attribute: .blue),
			macro,
		])
		
		#expect(!programmer.macroOverridesMix)
		programmer.set(120, of: macro)
		#expect(programmer.macroOverridesMix)
		programmer.releaseMix()
		#expect(!programmer.macroOverridesMix)
	}
}
