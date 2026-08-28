import XCTest
@testable import sleight

final class PinchDetectorTests: XCTestCase {
    /// Synthetic hand: span (wrist→middle MCP) = 0.4; thumb/index straddle x by `pinchDist`.
    private func frame(pinchDist: Double) -> HandFrame {
        var pts = (0..<21).map { _ in LandmarkPoint(x: 0.5, y: 0.5) }
        pts[Landmark.wrist] = LandmarkPoint(x: 0.5, y: 0.9)
        pts[Landmark.middleMCP] = LandmarkPoint(x: 0.5, y: 0.5)
        pts[Landmark.thumbTip] = LandmarkPoint(x: 0.5 - pinchDist / 2, y: 0.7)
        pts[Landmark.indexTip] = LandmarkPoint(x: 0.5 + pinchDist / 2, y: 0.7)
        return HandFrame(side: .right, points: pts, timestamp: 0)
    }

    func testOpenHandDoesNotTrigger() {
        var d = PinchDetector()
        let r = d.update(frame(pinchDist: 0.8))
        XCTAssertFalse(r.isActive)
        XCTAssertEqual(r.amount, 2.0, accuracy: 0.01) // 0.8 / 0.4 span
    }

    func testCrossingOnThresholdActivates() {
        var d = PinchDetector()
        _ = d.update(frame(pinchDist: 0.5))
        let r = d.update(frame(pinchDist: 0.12)) // norm 0.30, clearly below onThreshold 0.35
        XCTAssertTrue(r.isActive)
    }

    func testHysteresisRequiresWiderRelease() {
        var d = PinchDetector()
        _ = d.update(frame(pinchDist: 0.5))
        _ = d.update(frame(pinchDist: 0.12))      // on (0.30 < 0.35)
        let r = d.update(frame(pinchDist: 0.16))  // 0.40 < off 0.42 → still on
        XCTAssertTrue(r.isActive)
        let r2 = d.update(frame(pinchDist: 0.20)) // 0.50 > 0.42 → off
        XCTAssertFalse(r2.isActive)
    }

    func testAmountIsScaleInvariant() {
        // Same gesture at half the hand size → same normalized amount.
        var d1 = PinchDetector()
        var d2 = PinchDetector()
        let close = d1.update(frame(pinchDist: 0.14)).amount
        // Build a half-scale frame: span 0.2, pinch 0.07 → ratio identical.
        var pts = (0..<21).map { _ in LandmarkPoint(x: 0.5, y: 0.5) }
        pts[Landmark.wrist] = LandmarkPoint(x: 0.5, y: 0.7)
        pts[Landmark.middleMCP] = LandmarkPoint(x: 0.5, y: 0.5)
        pts[Landmark.thumbTip] = LandmarkPoint(x: 0.5 - 0.035, y: 0.6)
        pts[Landmark.indexTip] = LandmarkPoint(x: 0.5 + 0.035, y: 0.6)
        let far = d2.update(HandFrame(side: .right, points: pts, timestamp: 0)).amount
        XCTAssertEqual(close, far, accuracy: 0.02)
    }
}