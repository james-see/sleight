import XCTest
@testable import sleight

final class ARPadLayoutTests: XCTestCase {
    func testFourPadsProduceFourRects() {
        let rects = ARPadLayout.compute(padCount: 4)
        XCTAssertEqual(rects.count, 4)
    }

    func testAllRectsWithinNormalizedBounds() {
        let rects = ARPadLayout.compute(padCount: 4)
        for r in rects {
            XCTAssertGreaterThanOrEqual(r.minX, 0)
            XCTAssertLessThanOrEqual(r.maxX, 1)
            XCTAssertGreaterThanOrEqual(r.minY, 0)
            XCTAssertLessThanOrEqual(r.maxY, 1)
        }
    }

    func testPadsDoNotOverlap() {
        let rects = ARPadLayout.compute(padCount: 4)
        for i in 0..<rects.count {
            for j in (i+1)..<rects.count {
                XCTAssertFalse(rects[i].intersects(rects[j]),
                    "pads \(i) and \(j) overlap")
            }
        }
    }

    func testTwoPadsProduceTwoRects() {
        let rects = ARPadLayout.compute(padCount: 2)
        XCTAssertEqual(rects.count, 2)
    }

    func testThreePadsProduceThreeRects() {
        let rects = ARPadLayout.compute(padCount: 3)
        XCTAssertEqual(rects.count, 3)
    }

    func testTwelvePadsProduceTwelveRects() {
        let rects = ARPadLayout.compute(padCount: 12)
        XCTAssertEqual(rects.count, 12)
    }

    func testTwelvePadsDoNotOverlap() {
        let rects = ARPadLayout.compute(padCount: 12)
        for i in 0..<rects.count {
            for j in (i+1)..<rects.count {
                XCTAssertFalse(rects[i].intersects(rects[j]),
                    "pads \(i) and \(j) overlap")
            }
        }
    }

    func testPadCentersMapToDistinctNotes() {
        let root = 60
        let octaves: Double = 1
        let rects = ARPadLayout.compute(padCount: 4, columns: 1)
        let notes = rects.map { r -> Double in
            let yNorm = r.midY
            return Double(root) + yNorm * 12 * octaves
        }
        XCTAssertEqual(Set(notes).count, 4)
    }

    func testPadNotesMatchScale() {
        let notes = ARPadLayout.padNotes(padCount: 5, scale: .minorPentatonic, root: 60, octaves: 2)
        XCTAssertEqual(notes.count, 5)
        // Minor pentatonic intervals from C: 0, 3, 5, 7, 10 → C, Eb, F, G, Bb
        XCTAssertEqual(notes[0], 60)  // C4
        XCTAssertEqual(notes[1], 63)  // Eb4
        XCTAssertEqual(notes[2], 65)  // F4
        XCTAssertEqual(notes[3], 67)  // G4
        XCTAssertEqual(notes[4], 70)  // Bb4
    }

    func testPadNotesChromatic() {
        let notes = ARPadLayout.padNotes(padCount: 12, scale: .chromatic, root: 60, octaves: 1)
        XCTAssertEqual(notes.count, 12)
        XCTAssertEqual(notes[0], 60)
        XCTAssertEqual(notes[11], 71)
    }

    func testPadNotesMajor() {
        let notes = ARPadLayout.padNotes(padCount: 7, scale: .major, root: 60, octaves: 2)
        XCTAssertEqual(notes.count, 7)
        XCTAssertEqual(notes[0], 60)  // C
        XCTAssertEqual(notes[1], 62)  // D
        XCTAssertEqual(notes[2], 64)  // E
        XCTAssertEqual(notes[3], 65)  // F
        XCTAssertEqual(notes[4], 67)  // G
        XCTAssertEqual(notes[5], 69)  // A
        XCTAssertEqual(notes[6], 71)  // B
    }

    func testPadNotesMinor() {
        let notes = ARPadLayout.padNotes(padCount: 7, scale: .minor, root: 60, octaves: 2)
        XCTAssertEqual(notes.count, 7)
        XCTAssertEqual(notes[0], 60)  // C
        XCTAssertEqual(notes[1], 62)  // D
        XCTAssertEqual(notes[2], 63)  // Eb
        XCTAssertEqual(notes[3], 65)  // F
        XCTAssertEqual(notes[4], 67)  // G
        XCTAssertEqual(notes[5], 68)  // Ab
        XCTAssertEqual(notes[6], 70)  // Bb
    }
}