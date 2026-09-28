import Testing

@testable import Glow

struct FrameStreamTests {
	@Test func theFirstFrameGoesOutWhole() {
		var stream = FrameStream()
		let runs = stream.next([UInt8](repeating: 0, count: 512))
		
		#expect(runs.count == 1)
		#expect(runs.first?.start.value == 1)
		#expect(runs.first?.values.count == 512)
	}
	
	@Test func anUnchangedFrameIsNotSentAgain() {
		var stream = FrameStream()
		let values = [UInt8](repeating: 0, count: 512)
		_ = stream.next(values)
		
		#expect(stream.next(values).isEmpty)
	}
	
	@Test func onlyTheChangedChannelsGoOutWithoutWhatLiesBetween() {
		var stream = FrameStream()
		var values = [UInt8](repeating: 0, count: 512)
		_ = stream.next(values)
		values[9] = 5
		values[10] = 6
		values[12] = 7
		let runs = stream.next(values)
		
		#expect(runs.map(\.start.value) == [10, 13])
		#expect(runs.map(\.values) == [[5, 6], [7]])
	}
	
	@Test func startingOverSendsEverythingEvenWhenNothingMoved() {
		var stream = FrameStream()
		let values = [UInt8](repeating: 3, count: 512)
		_ = stream.next(values)
		stream.startOver()
		
		#expect(stream.next(values).first?.values.count == 512)
	}
	
	@Test func anAdoptedFrameIsNotEchoedBack() {
		var stream = FrameStream()
		var universe = Universe()
		_ = stream.next(universe.values)
		stream.adopt([(DMXAddress(5)!, [99])], ack: stream.sent, into: &universe)
		
		#expect(universe[DMXAddress(5)!] == 99)
		#expect(stream.next(universe.values).isEmpty)
	}
	
	@Test func theLastChannelIsReachable() {
		var stream = FrameStream()
		var values = [UInt8](repeating: 0, count: 512)
		_ = stream.next(values)
		values[511] = 1
		let runs = stream.next(values)
		
		#expect(runs.first?.start.value == 512)
		#expect(runs.first?.values == [1])
	}
	
	@Test func theFirstFrameCoversOnlyTheSpan() {
		var stream = FrameStream()
		stream.cover(120)
		var universe = [UInt8](repeating: 0, count: 512)
		universe[300] = 255
		
		#expect(stream.next(universe).first?.values.count == 120)
		#expect(stream.next(universe).isEmpty)
	}
	
	@Test func wideningTheSpanSendsNothingThatDidNotChange() {
		var stream = FrameStream()
		stream.cover(24)
		let universe = [UInt8](repeating: 5, count: 512)
		_ = stream.next(universe)
		stream.cover(120)
		
		#expect(stream.next(universe).isEmpty)
	}
	
	@Test func adoptingAnotherDevicesSlotKeepsALocalChangeElsewherePending() {
		var stream = FrameStream()
		var universe = Universe()
		_ = stream.next(universe.values)
		universe[DMXAddress(3)!] = 7
		stream.adopt([(DMXAddress(10)!, [5])], ack: stream.sent, into: &universe)
		let runs = stream.next(universe.values)
		
		#expect(runs.map(\.start.value) == [3])
		#expect(runs.map(\.values) == [[7]])
	}
	
	@Test func aWholeUniverseAdoptedOnConnectIsNotSentBack() {
		var stream = FrameStream()
		var universe = Universe()
		stream.cover(120)
		stream.adopt([(DMXAddress(1)!, [UInt8](repeating: 4, count: 512))], ack: 0, into: &universe)
		
		#expect(universe[DMXAddress(512)!] == 4)
		#expect(stream.next(universe.values).isEmpty)
	}
	
	@Test func aPartialAdoptOnConnectStillSendsEverything() {
		var stream = FrameStream()
		var universe = Universe()
		stream.cover(120)
		stream.adopt([(DMXAddress(10)!, [4, 4, 4, 4, 4])], ack: 0, into: &universe)
		
		#expect(stream.next(universe.values).first?.values.count == 120)
	}
	
	@Test func aValueSentBeforeTheControllerSawANewerLocalWriteIsIgnored() {
		var stream = FrameStream()
		var universe = Universe()
		_ = stream.next(universe.values)
		let before = stream.sent
		universe[DMXAddress(8)!] = 200
		_ = stream.next(universe.values)
		stream.adopt([(DMXAddress(8)!, [90]), (DMXAddress(9)!, [30])], ack: before, into: &universe)
		
		#expect(universe[DMXAddress(8)!] == 200)
		#expect(universe[DMXAddress(9)!] == 30)
		
		stream.adopt([(DMXAddress(8)!, [90])], ack: stream.sent, into: &universe)
		
		#expect(universe[DMXAddress(8)!] == 90)
		#expect(stream.next(universe.values).isEmpty)
	}
	
	@Test func aLocalChangeNotSentYetIsNotOverwrittenByAnIncomingValue() {
		var stream = FrameStream()
		var universe = Universe()
		_ = stream.next(universe.values)
		universe[DMXAddress(8)!] = 77
		stream.adopt([(DMXAddress(8)!, [150]), (DMXAddress(9)!, [30])], ack: stream.sent, into: &universe)
		
		#expect(universe[DMXAddress(8)!] == 77)
		#expect(universe[DMXAddress(9)!] == 30)
		#expect(stream.next(universe.values).map(\.values) == [[77]])
	}
	
	@Test func anAcknowledgementPastTheSixteenBitWrapStillCounts() {
		var stream = FrameStream()
		var universe = Universe()
		
		for step in 0..<70_000 {
			universe[DMXAddress(1)!] = UInt8(step % 2)
			_ = stream.next(universe.values)
		}
		
		stream.adopt([(DMXAddress(1)!, [77])], ack: stream.sent & 0xFFFF, into: &universe)
		
		#expect(universe[DMXAddress(1)!] == 77)
	}
	
	@Test func runsReadBackAsWritten() throws {
		let frame = Wire.frame([(DMXAddress(1)!, [9]), (DMXAddress(510)!, [1, 2, 3])], seq: 70_001)
		let read = try #require(Wire.runs(in: [UInt8](frame)))
		
		#expect(read.ack == 70_001 & 0xFFFF)
		#expect(read.runs.map(\.start.value) == [1, 510])
		#expect(read.runs.map(\.values) == [[9], [1, 2, 3]])
		#expect(Wire.runs(in: [UInt8](Wire.frame([(DMXAddress(511)!, [1, 2, 3])], seq: 0))) == nil)
	}
}
