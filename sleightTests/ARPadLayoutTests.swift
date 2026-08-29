import XCTest
@testable import sleight

final class ARPadLayoutTests: XCTestCase {
    func testFourPadsProduceFourRects() {
        let rects = ARPadLayout.compute(voiceCount: 4)
        XCTAssertEqual(rects.count, 4)
    }

    func testAllRectsWithinNormalizedBounds() {
        let rects = ARPadLayout.compute(voiceCount: 4)
        for r in rects {
            XCTAssertGreaterThanOrEqual(r.minX, 0)
            XCTAssertLessThanOrEqual(r.maxX, 1)
            XCTAssertGreaterThanOrEqual(r.minY, 0)
            XCTAssertLessThanOrEqual(r.maxY, 1)
        }
    }

    func testPadsDoNotOverlap() {
        let rects = ARPadLayout.compute(voiceCount: 4)
        for i in 0..<rects.count {
            for j in (i+1)..<rects.count {
                XCTAssertFalse(rects[i].intersects(rects[j]),
                    "pads \(i) and \(j) overlap")
            }
        }
    }

    func testTwoVoicesProduceTwoRects() {
        let rects = ARPadLayout.compute(voiceCount: 2)
        XCTAssertEqual(rects.count, 2)
    }

    func testThreeVoicesProduceThreeRects() {
        let rects = ARPadLayout.compute(voiceCount: 3)
        XCTAssertEqual(rects.count, 3)
    }

    func testPadCentersMapToDistinctNotes() {
        let root = 60
        let octaves: Double = 1
        // Use columns: 1 so every pad is in its own row (distinct Y).
        let rects = ARPadLayout.compute(voiceCount: 4, columns: 1)
        let notes = rects.map { r -> Double in
            let yNorm = r.midY  // center Y of pad
            return Double(root) + yNorm * 12 * octaves
        }
        // All distinct (different Y positions)
        XCTAssertEqual(Set(notes).count, 4)
    }
}