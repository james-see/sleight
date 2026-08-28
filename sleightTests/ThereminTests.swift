import XCTest
@testable import sleight

final class ThereminTests: XCTestCase {
    /// Synthetic right hand whose index tip sits at (x, y) with a given pinch
    /// separation (normalized by the synthetic span of 0.4).
    private func rightHand(x: Double, y: Double, pinchNorm: Double) -> HandFrame {
        var pts = (0..<21).map { _ in LandmarkPoint(x: 0.5, y: 0.5) }
        pts[Landmark.wrist] = LandmarkPoint(x: x, y: y + 0.4)
        pts[Landmark.middleMCP] = LandmarkPoint(x: x, y: y)
        pts[Landmark.thumbTip] = LandmarkPoint(x: x - pinchNorm * 0.2, y: y)
        pts[Landmark.indexTip] = LandmarkPoint(x: x + pinchNorm * 0.2, y: y)
        return HandFrame(side: .right, points: pts, timestamp: 0)
    }

    private func leftHand(y: Double) -> HandFrame {
        var pts = (0..<21).map { _ in LandmarkPoint(x: 0.2, y: y) }
        pts[Landmark.wrist] = LandmarkPoint(x: 0.2, y: y)
        return HandFrame(side: .left, points: pts, timestamp: 0)
    }

    func testPinchStartsNoteAndEmitsBendAndCC7() {
        let t = Theremin()
        let evs = t.update(hands: [rightHand(x: 0.75, y: 0.5, pinchNorm: 0.2),
                                   leftHand(y: 0.4)], dt: 1/60)
        XCTAssertTrue(evs.contains { if case .noteOn = $0.kind { return true }; return false })
        XCTAssertTrue(evs.contains { if case .pitchBendSemitones = $0.kind { return true }; return false })
        XCTAssertTrue(evs.contains { if case .cc(7, _) = $0.kind { return true }; return false })
    }

    func testHandXMapsToPitchMonotonically() {
        let t = Theremin()
        func pitchFor(_ x: Double) -> Double {
            _ = t.update(hands: [rightHand(x: x, y: 0.5, pinchNorm: 0.2)], dt: 1/60)
            return t.currentPitch
        }
        let lo = pitchFor(0.56)
        let hi = pitchFor(0.94)
        XCTAssertGreaterThan(hi, lo + 6) // spans most of the 2-octave range
    }

    func testVolumeFloorReleasesNote() {
        let t = Theremin()
        _ = t.update(hands: [rightHand(x: 0.75, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)], dt: 1/60)
        XCTAssertTrue(t.isGateOpen)
        let evs = t.update(hands: [rightHand(x: 0.75, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.95)], dt: 1/60)
        XCTAssertFalse(t.isGateOpen)
        XCTAssertTrue(evs.contains { if case .noteOff = $0.kind { return true }; return false })
    }

    func testHandLostEmitsNoteOff() {
        let t = Theremin()
        _ = t.update(hands: [rightHand(x: 0.75, y: 0.5, pinchNorm: 0.2)], dt: 1/60)
        XCTAssertTrue(t.isGateOpen)
        let evs = t.update(hands: [], dt: 1/60)
        XCTAssertFalse(t.isGateOpen)
        XCTAssertTrue(evs.contains { if case .noteOff = $0.kind { return true }; return false })
    }

    func testScaleQuantizationChoosesPentatonicTones() {
        let t = Theremin()
        t.scale = .minorPentatonic
        _ = t.update(hands: [rightHand(x: 0.75, y: 0.5, pinchNorm: 0.2)], dt: 1/60)
        let pc = ((Int(t.currentPitch.rounded()) % 12) + 12) % 12
        XCTAssertTrue([0, 3, 5, 7, 10].contains(pc), "pitch \(t.currentPitch) pc \(pc) not in scale")
    }

    func testNoStuckNoteAcrossRandomizedHandLoss() {
        let t = Theremin()
        // play, then hand vanishes repeatedly
        for i in 0..<30 {
            let hands: [HandFrame] = i % 3 == 0
                ? []
                : [rightHand(x: 0.75, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)]
            _ = t.update(hands: hands, dt: 1/60)
            if i % 3 == 0 { XCTAssertFalse(t.isGateOpen) }
        }
        // final hand-loss must always release
        _ = t.update(hands: [], dt: 1/60)
        XCTAssertNil(t.currentNote)
        XCTAssertFalse(t.isGateOpen)
    }
}