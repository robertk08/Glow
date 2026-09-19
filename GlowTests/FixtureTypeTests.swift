import Foundation
import Testing

@testable import Glow

struct FixtureTypeTests {
	private func type(_ channels: [FixtureChannel], mixing: ColorMixing = .additive) -> FixtureType {
		FixtureType(id: "t", model: "T", mixing: mixing, channels: channels)
	}
	
	@Test func aDedicatedDimmerChannelIsTheDimmer() {
		let found = type([FixtureChannel(offset: 1, attribute: .dimmer)])
		
		guard case .channel = found.dimming else {
			Issue.record("expected a dedicated dimmer")
			return
		}
		
		#expect(found.dims)
	}
	
	@Test func aDeclaredDimBandIsTheDimmer() {
		var shutter = FixtureChannel(offset: 1, attribute: .shutter)
		shutter.functions = [
			ChannelFunction(from: 0, to: 9, label: "Zu", purpose: .closed),
			ChannelFunction(from: 10, to: 210, label: "Helligkeit", kind: .proportional, purpose: .dim),
			ChannelFunction(from: 211, to: 255, label: "Blitzer", kind: .proportional),
		]
		
		guard case let .band(_, from, to, _) = type([shutter]).dimming else {
			Issue.record("expected a dim band")
			return
		}
		
		#expect(from == 10)
		#expect(to == 210)
	}
	
	@Test func aBandThatSaysNothingIsNotADimmer() {
		var shutter = FixtureChannel(offset: 1, attribute: .shutter)
		shutter.functions = [ChannelFunction(from: 0, to: 255, label: "Dimmer", kind: .proportional)]
		
		#expect(type([shutter]).dimming == .none)
	}
	
	@Test func emittersDimAFixtureWithNoDimmer() {
		let channels = [FixtureChannel(offset: 1, attribute: .red), FixtureChannel(offset: 2, attribute: .green), FixtureChannel(offset: 3, attribute: .blue)]
		
		guard case let .emitters(found) = type(channels).dimming else {
			Issue.record("expected the emitters to dim")
			return
		}
		
		#expect(found.count == 3)
		#expect(type(channels).mixesColor)
	}
	
	@Test func subtractiveFlagsNeverDim() {
		let channels = [FixtureChannel(offset: 1, attribute: .cyan), FixtureChannel(offset: 2, attribute: .magenta), FixtureChannel(offset: 3, attribute: .yellow)]
		let found = type(channels, mixing: .subtractive)
		
		#expect(found.dimming == .none)
		#expect(found.mixesColor)
	}
	
	@Test func aWideChannelOwnsBothAddresses() {
		let found = type([FixtureChannel(offset: 1, attribute: .pan, fineOffset: 2, defaultValue: 128, fineDefaultValue: 7)])
		
		#expect(found.channelCount == 2)
		#expect(found.channel(.pan)?.maximum == 65535)
		#expect(found.channel(.pan)?.neutral == 128 * 256 + 7)
		#expect(found.defaults == [128, 7])
	}
	
	@Test func defaultsLandOnTheirOwnAddresses() {
		let found = type([FixtureChannel(offset: 1, attribute: .dimmer, defaultValue: 255), FixtureChannel(offset: 3, attribute: .pan, defaultValue: 128)])
		
		#expect(found.defaults == [255, 0, 128])
	}
	
	@Test func aChannelSetIsFoundInsideItsFunction() {
		var gobo = FixtureChannel(offset: 1, attribute: .gobo)
		var wheel = ChannelFunction(from: 6, to: 89, label: "Gobo")
		wheel.sets = [ChannelSet(from: 6, to: 17, label: "Gobo 1"), ChannelSet(from: 18, to: 29, label: "Gobo 2")]
		gobo.functions = [ChannelFunction(from: 0, to: 5, label: "Open", purpose: .open), wheel]
		
		#expect(gobo.function(containing: 20)?.set(containing: 20)?.label == "Gobo 2")
		#expect(gobo.function(containing: 2)?.purpose == .open)
	}
	
	@Test func aPhysicalRangeReadsInItsOwnUnit() {
		var zoom = ChannelFunction(from: 0, to: 255, label: "Narrow to wide", kind: .proportional)
		zoom.unit = .degrees
		zoom.physicalFrom = 5
		zoom.physicalTo = 35
		
		#expect(zoom.physical(at: 0) == "5°")
		#expect(zoom.physical(at: 255) == "35°")
		#expect(zoom.physical(at: 128) == "20°")
	}
	
	@Test func highlightFallsBackToTheOpenFunction() {
		var shutter = FixtureChannel(offset: 1, attribute: .shutter)
		shutter.functions = [ChannelFunction(from: 0, to: 7, label: "Closed", purpose: .closed), ChannelFunction(from: 240, to: 255, label: "Open", purpose: .open)]
		
		#expect(shutter.highlight == 240)
		#expect(FixtureChannel(offset: 1, attribute: .dimmer).highlight == 255)
		#expect(FixtureChannel(offset: 1, attribute: .zoom).highlight == nil)
	}
	
	@Test func aDefinitionSurvivesARoundTrip() throws {
		var channel = FixtureChannel(offset: 1, attribute: .gobo, label: "Gobo wheel", fineOffset: 2, defaultValue: 4, highlightValue: 9)
		var function = ChannelFunction(from: 6, to: 89, label: "Gobo", kind: .proportional, purpose: .dim)
		function.unit = .hertz
		function.physicalFrom = 1
		function.physicalTo = 20
		function.sets = [ChannelSet(from: 6, to: 17, label: "Gobo 1", colors: ["ff0000"])]
		channel.functions = [function]
		let made = FixtureType(id: "x", manufacturer: "M", model: "X", mode: "one", symbol: "star", mixing: .subtractive, invertsPan: true, panDegrees: 540, channels: [channel])
		
		let back = try JSONDecoder().decode(FixtureType.self, from: JSONEncoder().encode(made))
		
		#expect(back == made)
	}
	
	@Test func aChannelIsGroupedByWhatItDrives() {
		#expect(Attribute.gobo.group == .gobo)
		#expect(Attribute.cyan.group == .color)
		#expect(Attribute.tilt.group == .position)
		#expect(Attribute.frost.group == .beam)
		#expect(Attribute.dimmer.group == .dimmer)
		#expect(Attribute.reset.group == .control)
	}
}
