import XCTest
@testable import sleight

final class PolyPadsARTests: XCTestCase {
    private var pads: PolyPads!

    override func setUp() {
        pads = PolyPads()
        pads.voiceCount = 4
        pads.root = 60
        pads.octaves = 1
        pads.scale = .chromatic
        pads.padLayout = ARPadLayout.compute(voiceCount: 4)
    }

    private func rightHand(tipIndex: Int, tipX: Double, tipY: Double) -> HandFrame {
        var pts: [LandmarkPoint] = []
        for i in 0..<21 {
            let y: Double
            switch i {
            case 0: y = 0.7
            case 8, 12, 16, 20: y = (i == tipIndex) ? tipY : 0.5
            case 5, 9, 13, 17: y = 0.5
            default: y = 0.5
            }
            pts.append(LandmarkPoint(x: 0.5, y: y, confidence: 1.0))
        }
        return HandFrame(side: .right, points: pts, timestamp: 0)
    }

    /// Helper: compute the expected note from a Y value through pitchBand + quantize.
    private func expectedNote(forY y: Double) -> UInt8 {
        let band = pads.pitchBand
        let yNorm = min(max((y - band.lowerBound) / (band.upperBound - band.lowerBound), 0), 1)
        let rawPitch = Double(pads.root) + yNorm * 12 * pads.octaves
        let quantized = MusicTheory.quantize(rawPitch, scale: pads.scale, root: pads.root % 12)
        return UInt8(quantized.rounded())
    }

    func testFingerInsidePadSnapsToPadNote() {
        guard let pad0 = pads.padLayout?.first else {
            XCTFail("no pad layout"); return
        }
        // Place index finger at the center of pad 0
        let hand = rightHand(tipIndex: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY))
        let evs = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertFalse(noteOns.isEmpty)

        // The note should match the pad's center Y -> pitch formula
        let expected = expectedNote(forY: Double(pad0.midY))
        if case .noteOn(let n, _, _) = noteOns.first!.kind {
            XCTAssertEqual(n, expected, "note should snap to pad center pitch")
        }
    }

    func testFingerOutsidePadUsesContinuousYMapping() {
        // Place index finger at x=0.5 (outside pad X band 0.55-0.95), y=0.7 (extended)
        let hand = rightHand(tipIndex: 8, tipX: 0.5, tipY: 0.7)
        let evs = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        // Should still produce a note -- just from continuous Y, not snapped
        XCTAssertFalse(noteOns.isEmpty)
    }

    func testPadLayoutNilUsesContinuousMapping() {
        pads.padLayout = nil
        let hand = rightHand(tipIndex: 8, tipX: 0.5, tipY: 0.7)
        let evs = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertFalse(noteOns.isEmpty)
        // Should use the standard continuous formula (through pitchBand)
        let expected = expectedNote(forY: 0.7)
        if case .noteOn(let n, _, _) = noteOns.first!.kind {
            XCTAssertEqual(n, expected)
        }
    }

    // MARK: - Task 8: AR pads default + instrument-switch layout

    /// AR pads must be on by default for PolyPads: a freshly created
    /// AppSettings should have `arPadsEnabled == true`, and applying those
    /// settings through a SleightController with the PolyPads instrument
    /// selected should produce a non-nil `padLayout` on the PolyPads instance.
    @MainActor
    func testARPadsOnByDefaultForPolyPads() {
        // 1. AppSettings defaults arPadsEnabled to true.
        let settings = AppSettings()
        XCTAssertTrue(settings.arPadsEnabled,
            "arPadsEnabled must default to true so PolyPads shows pads out of the box")

        // 2. Wire a controller with PolyPads selected and confirm applySettings
        //    installs a non-nil pad layout derived from voiceCount.
        settings.instrumentRaw = InstrumentType.polyPads.rawValue
        settings.voiceCount = 4
        let controller = SleightController()
        // Replace the controller's settings so we control the state exactly.
        // (SleightController owns its own AppSettings; mutate it in place.)
        controller.settings.instrumentRaw = InstrumentType.polyPads.rawValue
        controller.settings.voiceCount = 4
        controller.settings.arPadsEnabled = true
        controller.applySettings()

        let inst = controller.pipeline.instrument
        guard let polyPads = inst as? PolyPads else {
            XCTFail("expected PolyPads instrument, got \(type(of: inst))"); return
        }
        XCTAssertNotNil(polyPads.padLayout, "PolyPads.padLayout must be set when arPadsEnabled is true")
        XCTAssertEqual(polyPads.padLayout?.count, 4, "pad layout should have one pad per voice")
        // The layout must match ARPadLayout.compute for the same voice count.
        let expected = ARPadLayout.compute(voiceCount: 4)
        XCTAssertEqual(polyPads.padLayout, expected,
            "pad layout must equal ARPadLayout.compute(voiceCount: settings.voiceCount)")
    }

    /// When the user switches to the PolyPads instrument, applySettings() must
    /// compute and install a fresh pad layout on the new PolyPads instance.
    /// This regression-tests the instrument-switch path in applySettings().
    @MainActor
    func testPolyPadsGetsPadLayoutOnInstrumentSwitch() {
        let controller = SleightController()
        // Start from the default theremin instrument.
        controller.settings.instrumentRaw = InstrumentType.theremin.rawValue
        controller.settings.arPadsEnabled = true
        controller.applySettings()
        // Theremin is NOT a PolyPads, so no pad layout applies yet.
        XCTAssertFalse(controller.pipeline.instrument is PolyPads,
            "precondition: theremin should be active before the switch")

        // Now switch to PolyPads — applySettings must build a new PolyPads and
        // install a pad layout derived from the current voice count.
        controller.settings.instrumentRaw = InstrumentType.polyPads.rawValue
        controller.settings.voiceCount = 3
        controller.applySettings()

        guard let polyPads = controller.pipeline.instrument as? PolyPads else {
            XCTFail("instrument should be PolyPads after switching to poly-pads"); return
        }
        XCTAssertNotNil(polyPads.padLayout,
            "PolyPads must receive a pad layout on instrument switch when arPadsEnabled is true")
        XCTAssertEqual(polyPads.padLayout?.count, 3,
            "pad layout count must match voiceCount (3) after instrument switch")
        XCTAssertEqual(polyPads.padLayout, ARPadLayout.compute(voiceCount: 3),
            "installed layout must equal ARPadLayout.compute(voiceCount: 3)")

        // Switching back to theremin then to PolyPads again must re-install the
        // layout (regression: the old PolyPads instance should not be reused).
        controller.settings.instrumentRaw = InstrumentType.theremin.rawValue
        controller.applySettings()
        controller.settings.instrumentRaw = InstrumentType.polyPads.rawValue
        controller.settings.voiceCount = 2
        controller.applySettings()
        guard let polyPads2 = controller.pipeline.instrument as? PolyPads else {
            XCTFail("instrument should be PolyPads after second switch"); return
        }
        XCTAssertEqual(polyPads2.padLayout?.count, 2,
            "pad layout must be recomputed for voiceCount=2 after a second switch")
        XCTAssertEqual(polyPads2.padLayout, ARPadLayout.compute(voiceCount: 2),
            "recomputed layout must equal ARPadLayout.compute(voiceCount: 2)")
    }
}