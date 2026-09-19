import Testing

@testable import Glow

struct FrameStreamTests {
	@Test func theFirstFrameGoesOutWhole() {
		var stream = FrameStream()
		let frame = stream.next([UInt8](repeating: 0, count: 512))
		
		#expect(frame?.start.value == 1)
		#expect(frame?.values.count == 512)
	}
	
	@Test func anUnchangedFrameIsNotSentAgain() {
		var stream = FrameStream()
		let values = [UInt8](repeating: 0, count: 512)
		_ = stream.next(values)
		
		#expect(stream.next(values) == nil)
	}
	
	@Test func onlyTheChangedSpanGoesOut() {
		var stream = FrameStream()
		var values = [UInt8](repeating: 0, count: 512)
		_ = stream.next(values)
		values[9] = 5
		values[11] = 7
		let frame = stream.next(values)
		
		#expect(frame?.start.value == 10)
		#expect(frame?.values == [5, 0, 7])
	}
	
	@Test func startingOverSendsEverythingEvenWhenNothingMoved() {
		var stream = FrameStream()
		let values = [UInt8](repeating: 3, count: 512)
		_ = stream.next(values)
		stream.startOver()
		
		#expect(stream.next(values)?.values.count == 512)
	}
	
	@Test func anAdoptedFrameIsNotEchoedBack() {
		var stream = FrameStream()
		var values = [UInt8](repeating: 0, count: 512)
		_ = stream.next(values)
		values[4] = 99
		stream.adopt(values)
		
		#expect(stream.next(values) == nil)
	}
	
	@Test func theLastChannelIsReachable() {
		var stream = FrameStream()
		var values = [UInt8](repeating: 0, count: 512)
		_ = stream.next(values)
		values[511] = 1
		let frame = stream.next(values)
		
		#expect(frame?.start.value == 512)
		#expect(frame?.values == [1])
	}
}
