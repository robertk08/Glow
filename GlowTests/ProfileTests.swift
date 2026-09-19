import Foundation
import Testing

@testable import Glow

struct ProfileTests {
	@Test func aDedicatedIntensityChannelIsTheDimmer() {
		let profile = FixtureProfile(id: "t", model: "T", channels: [ProfileChannel(offset: 1, role: .intensity)])
		
		guard case .channel = profile.dimming else {
			Issue.record("expected a dedicated dimmer")
			return
		}
		
		#expect(profile.dims)
	}
	
	@Test func aShutterWithADimBandIsTheDimmer() {
		let shutter = ProfileChannel(offset: 1, role: .shutter, ranges: [
			ChannelRange(from: 0, to: 9, label: "Closed"),
			ChannelRange(from: 10, to: 210, label: "Dimmer", kind: .proportional),
			ChannelRange(from: 211, to: 255, label: "Strobe", kind: .proportional),
		])
		let profile = FixtureProfile(id: "t", model: "T", channels: [shutter])
		
		guard case let .band(_, from, to, _) = profile.dimming else {
			Issue.record("expected a dim band")
			return
		}
		
		#expect(from == 10)
		#expect(to == 210)
	}
	
	@Test func emittersDimAFixtureWithNoDimmer() {
		let profile = FixtureProfile(id: "t", model: "T", channels: [
			ProfileChannel(offset: 1, role: .red),
			ProfileChannel(offset: 2, role: .green),
			ProfileChannel(offset: 3, role: .blue),
		])
		
		guard case let .emitters(channels) = profile.dimming else {
			Issue.record("expected the emitters to dim")
			return
		}
		
		#expect(channels.count == 3)
		#expect(profile.mixesColor)
	}
	
	@Test func subtractiveFlagsNeverDim() {
		let profile = FixtureProfile(id: "t", model: "T", channels: [
			ProfileChannel(offset: 1, role: .cyan),
			ProfileChannel(offset: 2, role: .magenta),
			ProfileChannel(offset: 3, role: .yellow),
		], mixing: .subtractive)
		
		#expect(profile.dimming == .none)
		#expect(!profile.dims)
		#expect(profile.mixesColor)
	}
	
	@Test func defaultsLandOnTheirOwnChannels() {
		let profile = FixtureProfile(id: "t", model: "T", channels: [
			ProfileChannel(offset: 1, role: .intensity, defaultValue: 255),
			ProfileChannel(offset: 3, role: .pan, defaultValue: 128),
		])
		
		#expect(profile.defaults == [255, 0, 128])
	}
	
	@Test func aFineChannelPairsWithItsCoarseOne() {
		let profile = FixtureProfile(id: "t", model: "T", channels: [
			ProfileChannel(offset: 1, role: .pan),
			ProfileChannel(offset: 2, role: .pan, isFine: true),
		])
		
		#expect(profile.channel(.pan)?.offset == 1)
		#expect(profile.channel(.pan, fine: true)?.offset == 2)
		#expect(profile.emitterChannels.isEmpty)
	}
	
	@Test func aReversedRangeIsPutBackInOrder() throws {
		let json = Data(#"{"from":200,"to":10,"label":"Backwards"}"#.utf8)
		let range = try JSONDecoder().decode(ChannelRange.self, from: json)
		
		#expect(range.from == 10)
		#expect(range.to == 200)
		#expect(range.contains(100))
	}
	
	@Test func aProfileCanDeclareItselfSubtractive() throws {
		let json = Data(#"{"id":"x","model":"X","colorMixing":"subtractive","channels":[{"offset":1,"role":"cyan"}]}"#.utf8)
		let profile = try JSONDecoder().decode(FixtureProfile.self, from: json)
		
		#expect(profile.mixing == .subtractive)
	}
	
	@Test func aProfileWithoutTheKeyIsAdditive() throws {
		let json = Data(#"{"id":"x","model":"X","channels":[{"offset":1,"role":"red"}]}"#.utf8)
		let profile = try JSONDecoder().decode(FixtureProfile.self, from: json)
		
		#expect(profile.mixing == .additive)
	}
	
	@Test func aShowFileWithNoVersionStillReads() throws {
		let json = Data(#"{"name":"Old","lights":[],"groups":[],"profiles":[],"scenes":[]}"#.utf8)
		let file = try JSONDecoder().decode(ShowFile.self, from: json)
		
		#expect(file.version == nil)
		#expect(file.name == "Old")
	}
	
	@Test func repeatedRolesPairWithTheirOwnFineChannels() {
		let profile = FixtureProfile(id: "t", model: "T", channels: [ProfileChannel(offset: 1, role: .custom), ProfileChannel(offset: 2, role: .custom, isFine: true, defaultValue: 7), ProfileChannel(offset: 3, role: .custom), ProfileChannel(offset: 4, role: .custom, isFine: true, defaultValue: 11)])
		#expect(profile.parameters.map { $0.fine?.offset } == [2, 4])
		#expect(profile.parameters.map(\.neutral) == [7, 11])
	}
	
	@Test func anEmptyProfileHasNoDefaults() {
		#expect(FixtureProfile(id: "t", model: "T", channels: []).defaults.isEmpty)
	}
	
	@Test func aShutterEffectIsNotMistakenForADimmer() {
		let shutter = ProfileChannel(offset: 1, role: .shutter, ranges: [ChannelRange(from: 0, to: 255, label: "Random pulse", kind: .proportional)])
		#expect(FixtureProfile(id: "t", model: "T", channels: [shutter]).dimming == .none)
	}
}
