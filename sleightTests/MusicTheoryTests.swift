import XCTest
@testable import sleight

final class MusicTheoryTests: XCTestCase {
    func testChromaticQuantizeRoundsToNearestSemitone() {
        XCTAssertEqual(MusicTheory.quantize(60.4, scale: .chromatic, root: 0), 60.0)
        XCTAssertEqual(MusicTheory.quantize(60.6, scale: .chromatic, root: 0), 61.0)
        XCTAssertEqual(MusicTheory.quantize(60.5, scale: .chromatic, root: 0), 61.0) // .5 rounds up
    }

    func testMajorQuantizeSnapsToNearestScaleTone() {
        // C major: allowed pcs {0,2,4,5,7,9,11}
        XCTAssertEqual(MusicTheory.quantize(60.9, scale: .major, root: 0), 60.0)  // nearer 60 than 62
        XCTAssertEqual(MusicTheory.quantize(61.1, scale: .major, root: 0), 62.0)  // nearer 62
        XCTAssertEqual(MusicTheory.quantize(58.8, scale: .major, root: 0), 59.0)  // B (pc 11) is in C major, dist 0.2
        XCTAssertEqual(MusicTheory.quantize(59.7, scale: .major, root: 0), 60.0)  // C beats B across the seam
    }

    func testQuantizeHandlesOctaveWindowCorrectly() {
        // 71.9 (B just below C5=72): candidates 71(B) dist .9, 72(C) dist .1 → 72
        XCTAssertEqual(MusicTheory.quantize(71.9, scale: .major, root: 0), 72.0)
        // Far outside ±12 must clamp to the nearest edge, not invent pitches.
        // 29(F) and 31(G) are both dist 1.0 from 30 — tie-break picks the lower note.
        XCTAssertEqual(MusicTheory.quantize(30.0, scale: .major, root: 0), 29.0)
        XCTAssertEqual(MusicTheory.quantize(90.0, scale: .major, root: 0), 89.0)  // 89(F) vs 91(G) tie → lower wins
    }

    func testFreeIsIdentity() {
        XCTAssertEqual(MusicTheory.quantize(61.37, scale: .free, root: 0), 61.37)
    }

    func testSubdivisionDuration() {
        XCTAssertEqual(NoteSubdivision.duration(bpm: 120, subdivision: .thirtySecond), 0.0625, accuracy: 1e-9)
        XCTAssertEqual(NoteSubdivision.duration(bpm: 120, subdivision: .sixteenth), 0.125, accuracy: 1e-9)
        XCTAssertEqual(NoteSubdivision.duration(bpm: 60, subdivision: .thirtySecond), 0.125, accuracy: 1e-9)
    }

    func testNoteNames() {
        XCTAssertEqual(MusicTheory.noteName(60), "C4")
        XCTAssertEqual(MusicTheory.noteName(61), "C#4")
        XCTAssertEqual(MusicTheory.noteName(59), "B3")
        XCTAssertEqual(MusicTheory.noteName(69), "A4")
    }
}