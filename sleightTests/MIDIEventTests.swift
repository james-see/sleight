import XCTest
@testable import sleight

final class MIDIEventTests: XCTestCase {
    func testNoteOnEncoding() {
        let e = MIDIEvent(kind: .noteOn(60, velocity: 100), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0x90, 60, 100])
    }

    func testNoteOffEncoding() {
        let e = MIDIEvent(kind: .noteOff(60), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0x80, 60, 0])
    }

    func testPitchBendCenter() {
        let e = MIDIEvent(kind: .pitchBendSemitones(0.0), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xE0, 0, 64]) // 8192 centered
    }

    func testPitchBendPositiveHalfRange() {
        // +1.0 semitone of ±2 → 8192 + round(0.5*8191) = 12288 → lsb 0, msb 96
        let e = MIDIEvent(kind: .pitchBendSemitones(1.0), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xE0, 0, 96])
    }

    func testPitchBendClampsOutOfRange() {
        let e = MIDIEvent(kind: .pitchBendSemitones(5.0), timestamp: 0) // beyond ±2
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xE0, 127, 127]) // max = 8192+8191
        // 14-bit bend is asymmetric: down span 8192 steps, up span 8191, so
        // clamped -1.0 → v=1 (one step shy of the raw extreme v=0). Standard.
        let e2 = MIDIEvent(kind: .pitchBendSemitones(-5.0), timestamp: 0)
        XCTAssertEqual(e2.encode(bendRangeSemitones: 2), [0xE0, 1, 0])
    }

    func testCC7Encoding() {
        let e = MIDIEvent(kind: .cc(7, 64), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xB0, 7, 64])
    }
}