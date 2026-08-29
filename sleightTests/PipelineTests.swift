import XCTest
@testable import sleight

final class PipelineTests: XCTestCase {
    func testDropPolicy() {
        XCTAssertFalse(DropPolicy.shouldProcess(lastDuration: 0.040, budget: 0.033, justDropped: false))
        XCTAssertTrue(DropPolicy.shouldProcess(lastDuration: 0.020, budget: 0.033, justDropped: false))
    }

    /// Regression: one over-budget frame (Vision warmup) used to wedge the
    /// pipeline permanently — lastDuration only updated on processed frames,
    /// so every later frame was dropped forever and hands never registered.
    /// The frame right after a drop must always process.
    func testDropPolicyRecoversAfterDrop() {
        // warmup frame overran the budget → dropped, justDropped latched
        XCTAssertFalse(DropPolicy.shouldProcess(lastDuration: 0.200, budget: 0.033, justDropped: false))
        // next frame processes even though lastDuration still reads slow
        XCTAssertTrue(DropPolicy.shouldProcess(lastDuration: 0.200, budget: 0.033, justDropped: true))
        // sustained overload degrades to half rate, never a wedge
        XCTAssertFalse(DropPolicy.shouldProcess(lastDuration: 0.200, budget: 0.033, justDropped: false))
        XCTAssertTrue(DropPolicy.shouldProcess(lastDuration: 0.200, budget: 0.033, justDropped: true))
    }

    @MainActor
    func testPracticeModeSuppressesMIDIButPublishesState() async {
        let model = PipelineModel()
        let settings = AppSettings()
        let p = Pipeline(model: model, settings: settings)
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
        let settings = AppSettings()
        let p = Pipeline(model: model, settings: settings)
        var pts = (0..<21).map { _ in LandmarkPoint(x: 0.7, y: 0.5) }
        pts[Landmark.indexTip] = LandmarkPoint(x: 0.9, y: 0.5)
        let frame = HandFrame(side: .right, points: pts, timestamp: 0)
        _ = p.processSynthetic([frame], dt: 1/60)
        XCTAssertNotNil(model.overlay.pitchX)
        XCTAssertTrue(model.overlay.trackingActive)
        XCTAssertEqual(model.overlay.skeleton[.right]?.count, 21)
    }

    @MainActor
    func testOverlayStateIncludesARPadsWhenEnabled() {
        let model = PipelineModel()
        let settings = AppSettings()
        settings.arPadsEnabled = true
        settings.instrumentRaw = InstrumentType.polyPads.rawValue
        settings.voiceCount = 4
        let p = Pipeline(model: model, settings: settings)
        let frame = HandFrame(
            side: .right,
            points: (0..<21).map { _ in LandmarkPoint(x: 0.7, y: 0.5) },
            timestamp: 0
        )
        _ = p.processSynthetic([frame], dt: 1/60)
        XCTAssertNotNil(model.overlay.arPads)
        XCTAssertEqual(model.overlay.arPads?.count, 4)
    }

    @MainActor
    func testARPadsNilWhenDisabled() {
        let model = PipelineModel()
        let settings = AppSettings()
        settings.arPadsEnabled = false
        let p = Pipeline(model: model, settings: settings)
        let frame = HandFrame(
            side: .right,
            points: (0..<21).map { _ in LandmarkPoint(x: 0.7, y: 0.5) },
            timestamp: 0
        )
        _ = p.processSynthetic([frame], dt: 1/60)
        XCTAssertNil(model.overlay.arPads)
    }

    @MainActor
    func testARPadsNilWhenInstrumentNotPolyPads() {
        let model = PipelineModel()
        let settings = AppSettings()
        settings.arPadsEnabled = true
        settings.instrumentRaw = InstrumentType.theremin.rawValue
        let p = Pipeline(model: model, settings: settings)
        let frame = HandFrame(
            side: .right,
            points: (0..<21).map { _ in LandmarkPoint(x: 0.7, y: 0.5) },
            timestamp: 0
        )
        _ = p.processSynthetic([frame], dt: 1/60)
        XCTAssertNil(model.overlay.arPads)
    }

    @MainActor
    func testARPadHitDetectedWhenFingerInsidePad() {
        let model = PipelineModel()
        let settings = AppSettings()
        settings.arPadsEnabled = true
        settings.instrumentRaw = InstrumentType.polyPads.rawValue
        settings.voiceCount = 4
        let p = Pipeline(model: model, settings: settings)

        // Compute the pad layout to know where to place a finger.
        let pads = ARPadLayout.compute(voiceCount: 4)
        let targetPad = pads[0]
        let tipX = Double(targetPad.midX)
        let tipY = Double(targetPad.midY)

        var pts = (0..<21).map { _ in LandmarkPoint(x: 0.5, y: 0.5) }
        pts[8] = LandmarkPoint(x: tipX, y: tipY, confidence: 1.0) // index tip in pad 0
        let frame = HandFrame(side: .right, points: pts, timestamp: 0)
        _ = p.processSynthetic([frame], dt: 1/60)

        XCTAssertTrue(model.overlay.arPadHits.contains(0),
            "pad 0 should be hit when index finger is inside it")
    }
}