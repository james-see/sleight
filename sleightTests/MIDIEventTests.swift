import XCTest
@testable import sleight

final class MIDIEventTests: XCTestCase {
    func testNoteOnEncoding() {
        let e = MIDIEvent(kind: .noteOn(note: 60, velocity: Double(100) / 127), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0x90, 60, 100])
    }

    func testNoteOffEncoding() {
        let e = MIDIEvent(kind: .noteOff(note: 60), timestamp: 1)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0x80, 60, 0])
    }

    // v1 semantics preserved: per-note bend still emits a channel bend (E0)
    // on the legacy path; the note number is carried but unused there.
    func testPitchBendCenter() {
        let e = MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 0.0), timestamp: 2)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xE0, 0, 64]) // 8192 centered
    }

    func testPitchBendPositiveHalfRange() {
        // +1.0 semitone of ±2 → 8192 + round(0.5*8191) = 12288 → lsb 0, msb 96
        let e = MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 1.0), timestamp: 3)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xE0, 0, 96])
    }

    func testPitchBendClampsOutOfRange() {
        let e = MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 5.0), timestamp: 4)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xE0, 127, 127]) // 8192+8191
        // 14-bit bend is asymmetric: down span 8192 steps, up span 8191, so
        // clamped -1.0 → v=1 (one step shy of the raw extreme v=0). Standard.
        let e2 = MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, -5.0), timestamp: 5)
        XCTAssertEqual(e2.encode(bendRangeSemitones: 2), [0xE0, 1, 0])
    }

    func testCC7Encoding() {
        let e = MIDIEvent(kind: .cc(7, 64), timestamp: 6)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xB0, 7, 64])
    }
}