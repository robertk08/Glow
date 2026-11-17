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
		programmer.set(3, of: macro)
		#expect(!programmer.macroOverridesMix)
	}
	
	@Test func aLightThatDimsThroughItsColoursStillGetsAnIntensityPage() {
		let (_, programmer) = rig([
			FixtureChannel(offset: 1, attribute: .red),
			FixtureChannel(offset: 2, attribute: .green),
			FixtureChannel(offset: 3, attribute: .blue),
		])
		
		#expect(programmer.groups.first == .dimmer)
	}
	
	@Test func mixedLightsShareWhatMatchesAndKeepWhatOnlyOneHas() {
		var gobo = FixtureChannel(offset: 4, attribute: .gobo)
		gobo.functions = [ChannelFunction(from: 0, to: 127, label: "Open"), ChannelFunction(from: 128, to: 255, label: "Star")]
		var otherGobo = FixtureChannel(offset: 2, attribute: .gobo)
		otherGobo.functions = [ChannelFunction(from: 0, to: 63, label: "Open"), ChannelFunction(from: 64, to: 255, label: "Ring")]
		let head = FixtureType(id: "head", model: "Head", channels: [FixtureChannel(offset: 1, attribute: .dimmer), FixtureChannel(offset: 2, attribute: .zoom), FixtureChannel(offset: 3, attribute: .shutter), gobo])
		let spot = FixtureType(id: "spot", model: "Spot", channels: [FixtureChannel(offset: 1, attribute: .shutter), otherGobo, FixtureChannel(offset: 3, attribute: .dimmer)])
		let fixtures = [Fixture(typeID: "head", name: "Head", address: DMXAddress(1)!, sortIndex: 0), Fixture(typeID: "spot", name: "Spot", address: DMXAddress(11)!, sortIndex: 1)]
		let console = Console()
		let programmer = Programmer(fixtures: fixtures, library: FixtureLibrary(builtIn: [head, spot]), console: console)
		
		#expect(programmer.channels.map(\.attribute) == [.dimmer, .zoom, .shutter])
		#expect(programmer.groups == [.dimmer, .beam])
		
		programmer.set(200, of: programmer.channel(.shutter)!)
		programmer.set(90, of: programmer.channel(.zoom)!)
		
		#expect(console.value(at: DMXAddress(3)!) == 200)
		#expect(console.value(at: DMXAddress(11)!) == 200)
		#expect(console.value(at: DMXAddress(2)!) == 90)
		#expect(console.value(at: DMXAddress(12)!) == 0)
	}
	
	@Test func everyChannelSitsOnThePageOfItsFeatureGroup() {
		let (_, programmer) = rig([
			FixtureChannel(offset: 1, attribute: .dimmer),
			FixtureChannel(offset: 2, attribute: .dimmerCurve),
			FixtureChannel(offset: 3, attribute: .pan),
			FixtureChannel(offset: 4, attribute: .tilt),
			FixtureChannel(offset: 5, attribute: .panTiltSpeed),
			FixtureChannel(offset: 6, attribute: .prism),
			FixtureChannel(offset: 7, attribute: .goboRotation),
			FixtureChannel(offset: 8, attribute: .program),
		])
		
		#expect(programmer.groups == [.dimmer, .position, .gobo, .beam, .control])
		#expect(programmer.extras(on: .dimmer).map(\.attribute) == [.dimmerCurve])
		#expect(programmer.extras(on: .beam).map(\.attribute) == [.prism])
		#expect(programmer.extras(on: .control).map(\.attribute) == [.program])
		#expect(programmer.extras(on: .position).map(\.attribute) == [.panTiltSpeed])
		#expect(programmer.extras(on: .gobo).map(\.attribute) == [.goboRotation])
		#expect(programmer.axes == [.pan, .tilt])
	}
	
	@Test func mixedMoversKeepBothSlidersWhenTheirPanChannelsDiffer() {
		let wide = FixtureType(id: "wide", model: "Wide", channels: [FixtureChannel(offset: 1, attribute: .pan, fineOffset: 2), FixtureChannel(offset: 3, attribute: .tilt), FixtureChannel(offset: 4, attribute: .panTiltSpeed)])
		let narrow = FixtureType(id: "narrow", model: "Narrow", channels: [FixtureChannel(offset: 1, attribute: .pan), FixtureChannel(offset: 2, attribute: .tilt), FixtureChannel(offset: 3, attribute: .panTiltSpeed)])
		let fixtures = [Fixture(typeID: "wide", name: "Wide", address: DMXAddress(1)!, sortIndex: 0), Fixture(typeID: "narrow", name: "Narrow", address: DMXAddress(11)!, sortIndex: 1)]
		let console = Console()
		let programmer = Programmer(fixtures: fixtures, library: FixtureLibrary(builtIn: [wide, narrow]), console: console)
		
		#expect(programmer.channel(.pan) == nil)
		#expect(programmer.axes == [.pan, .tilt])
		#expect(programmer.groups == [.position])
		#expect(programmer.extras(on: .position).map(\.attribute) == [.panTiltSpeed])
		
		programmer.setFraction(1, for: .pan)
		
		#expect(console.value(at: DMXAddress(1)!) == 255)
		#expect(console.value(at: DMXAddress(2)!) == 255)
		#expect(console.value(at: DMXAddress(11)!) == 255)
	}
	
	@Test func theDemoMoversKeepEachShutterOnBeamAndEachColorWheelOnColor() {
		let fixtures = [Fixture(typeID: "mini-moving-head-14ch", name: "Mover", address: DMXAddress(1)!, sortIndex: 0), Fixture(typeID: "stairville-bsw350-32ch", name: "Beam", address: DMXAddress(21)!, sortIndex: 1)]
		let programmer = Programmer(fixtures: fixtures, library: FixtureLibrary(), console: Console())
		
		#expect(programmer.groups == [.dimmer, .color, .position, .gobo, .beam, .control])
		#expect(programmer.extras(on: .dimmer).map(\.attribute) == [.dimmerCurve])
		#expect(programmer.extras(on: .color).map(\.attribute) == [.colorWheel, .cri])
		#expect(programmer.extras(on: .position).map(\.name) == ["Movement speed", "Movement macro"])
		#expect(programmer.extras(on: .beam).map(\.attribute) == [.shutter, .prism, .prismRotation, .frost])
		#expect(programmer.extras(on: .control).map(\.attribute) == [.programSpeed, .program, .reset, .control])
	}
	
	@Test func everyChannelSitsOnAPageTheSheetShowsAndNoPageIsEmpty() async throws {
		var state: UInt64 = 7
		
		for _ in 0..<300 {
			var channels: [FixtureChannel] = []
			
			for attribute in Attribute.allCases {
				state = state &* 6364136223846793005 &+ 1442695040888963407
				guard state >> 62 == 0 else { continue }
				var channel = FixtureChannel(offset: channels.count + 1, attribute: attribute)
				if state >> 58 & 7 == 0 { channel.functions = [ChannelFunction(from: 0, to: 127, label: "Dim", purpose: .dim), ChannelFunction(from: 128, to: 255, label: "Open", purpose: .open)] }
				channels.append(channel)
			}
			
			let (_, programmer) = rig(channels)
			let drawn: [FeatureGroup: [UUID?]] = [
				.dimmer: [programmer.channel(.dimmer)?.id] + programmer.extras(on: .dimmer).map(\.id),
				.color: programmer.emitterChannels.map(\.id) + [programmer.macroChannel?.id, programmer.temperatureChannel?.id] + programmer.extras(on: .color).map(\.id),
				.position: programmer.channels.filter { programmer.axes.contains($0.attribute) }.map(\.id) + programmer.extras(on: .position).map(\.id),
				.gobo: programmer.goboWheels.flatMap { [$0.id, programmer.spinner(of: $0)?.id] } + programmer.extras(on: .gobo).map(\.id),
				.beam: [programmer.shutterChannel?.id] + (programmer.channel(.zoom).map { [$0.id, programmer.channel(.focus)?.id] } ?? []) + programmer.extras(on: .beam).map(\.id),
				.control: programmer.extras(on: .control).map(\.id),
			]
			
			for channel in programmer.channels {
				#expect(programmer.groups.contains { drawn[$0]?.contains(channel.id) == true }, "\(channel.attribute) of \(channels.map(\.attribute)) is on no page among \(programmer.groups)")
			}
			
			for group in programmer.groups where group != .dimmer {
				#expect(drawn[group]?.contains { $0 != nil } == true, "\(group) is empty for \(channels.map(\.attribute))")
			}
			
			#expect(programmer.dims == programmer.groups.contains(.dimmer))
			try await Task.sleep(for: .milliseconds(1))
		}
	}
}
