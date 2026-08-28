import XCTest
@testable import sleight

final class PipelineTests: XCTestCase {
    func testDropPolicy() {
        XCTAssertFalse(DropPolicy.shouldProcess(lastDuration: 0.040, budget: 0.033))
        XCTAssertTrue(DropPolicy.shouldProcess(lastDuration: 0.020, budget: 0.033))
    }

    @MainActor
    func testPracticeModeSuppressesMIDIButPublishesState() async {
        let model = PipelineModel()
        let p = Pipeline(model: model)
        p.practiceMode = true // never emits MIDI during this test
        p.midiSource = nil

        let frame = HandFrame(
            side: .right,
            points: (0..<21).map { _ in LandmarkPoint(x: 0.7, y: 0.5) },
            timestamp: 0
        )
        let events = p.processSynthetic([frame], dt: 1/60)

        // events are still computed (Logic-less testing)…
        XCTAssertTrue(events.contains { if case .noteOn = $0.kind { return true }; return false })
        // …and overlay state is published
        XCTAssertTrue(model.overlay.trackingActive)
    }

    @MainActor
    func testOverlayStatePopulatedFromHands() {
        let model = PipelineModel()
        let p = Pipeline(model: model)
        var pts = (0..<21).map { _ in LandmarkPoint(x: 0.7, y: 0.5) }
        pts[Landmark.indexTip] = LandmarkPoint(x: 0.9, y: 0.5)
        let frame = HandFrame(side: .right, points: pts, timestamp: 0)
        _ = p.processSynthetic([frame], dt: 1/60)
        XCTAssertNotNil(model.overlay.pitchX)
        XCTAssertTrue(model.overlay.trackingActive)
        XCTAssertEqual(model.overlay.skeleton[.right]?.count, 21)
    }
}