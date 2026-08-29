import XCTest
@testable import sleight

final class ChannelAllocatorTests: XCTestCase {
    // MARK: MPE mode

    func testMPENoteOnAllocatesDistinctChannels() {
        var a = ChannelAllocator(mode: .mpe(maxVoices: 4))
        XCTAssertEqual(a.noteOn(voice: 0), 1)
        XCTAssertEqual(a.noteOn(voice: 1), 2)
        XCTAssertEqual(a.noteOn(voice: 2), 3)
        XCTAssertEqual(a.noteOn(voice: 3), 4)
    }

    func testMPENoteOffReclaimsChannel() {
        var a = ChannelAllocator(mode: .mpe(maxVoices: 4))
        _ = a.noteOn(voice: 0)
        _ = a.noteOn(voice: 1)
        a.noteOff(voice: 0)
        XCTAssertEqual(a.channel(for: 0), 0)
        XCTAssertEqual(a.channel(for: 1), 2)
        XCTAssertEqual(a.noteOn(voice: 0), 1)
    }

    func testVoiceStealingWhenFull() {
        var a = ChannelAllocator(mode: .mpe(maxVoices: 2))
        _ = a.noteOn(voice: 0)
        _ = a.noteOn(voice: 1)
        XCTAssertEqual(a.noteOn(voice: 0), 1)
    }

    func testResetClearsAll() {
        var a = ChannelAllocator(mode: .mpe(maxVoices: 4))
        _ = a.noteOn(voice: 0); _ = a.noteOn(voice: 1); _ = a.noteOn(voice: 2)
        a.reset()
        for v in 0..<4 { XCTAssertEqual(a.channel(for: v), 0) }
    }

    // MARK: UMP mode

    func testUMPAlwaysChannelZero() {
        var a = ChannelAllocator(mode: .ump)
        XCTAssertEqual(a.noteOn(voice: 0), 0)
        XCTAssertEqual(a.noteOn(voice: 3), 0)
        XCTAssertEqual(a.channel(for: 2), 0)
    }

    // MARK: Legacy mode

    func testLegacyAlwaysChannelZero() {
        var a = ChannelAllocator(mode: .legacy)
        XCTAssertEqual(a.noteOn(voice: 0), 0)
        XCTAssertEqual(a.channel(for: 0), 0)
    }
}
