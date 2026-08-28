import XCTest
@testable import sleight

final class HandTrackerTests: XCTestCase {
    private func fixture() -> [Int: (x: Double, y: Double, c: Double)] {
        var f: [Int: (x: Double, y: Double, c: Double)] = [:]
        for i in 0..<21 { f[i] = (Double(i) / 21.0, 0.5, 0.9) }
        f[7] = (0.1, 0.5, 0.2)  // low confidence point
        return f
    }

    func testMakeFrameMirrorsXForSelfieView() {
        let frame = VisionHandTracker.makeFrame(side: .right, points: fixture(), timestamp: 1.0)
        XCTAssertEqual(frame.points.count, 21)
        XCTAssertEqual(frame.points[3].x, 1.0 - Double(3) / 21.0, accuracy: 1e-9)
        XCTAssertEqual(frame.points[0].y, 0.5, accuracy: 1e-9)
    }

    func testLowConfidencePointInheritsNeighborPosition() {
        let frame = VisionHandTracker.makeFrame(side: .right, points: fixture(), timestamp: 1.0)
        XCTAssertEqual(frame.points[7].x, frame.points[6].x, accuracy: 1e-9)
        XCTAssertEqual(frame.points[7].confidence, 0.0)
    }

    func testMissingLeadingPointFallsBackToCenter() {
        var f = fixture()
        f[0] = nil // wrist missing entirely
        let frame = VisionHandTracker.makeFrame(side: .left, points: f, timestamp: 2.0)
        XCTAssertEqual(frame.points[0].x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(frame.points[0].confidence, 0.0)
        // next good point (index 1) still lands correctly
        XCTAssertEqual(frame.points[1].x, 1.0 - 1.0/21.0, accuracy: 1e-9)
    }

    /// Vision normalized coords are bottom-left origin; published frames must
    /// be top-down (SwiftUI Canvas + volume band both assume it). A raw y of
    /// 0.25 (low in Vision space) must publish as 0.75 (low on screen).
    func testMakeFrameFlipsYFromVisionBottomLeftOrigin() {
        var f = fixture()
        for i in 0..<21 { f[i]?.y = 0.25 }
        let frame = VisionHandTracker.makeFrame(side: .right, points: f, timestamp: 1.0)
        XCTAssertEqual(frame.points[0].y, 0.75, accuracy: 1e-9)
        XCTAssertEqual(frame.points[10].y, 0.75, accuracy: 1e-9)
    }
}