import XCTest
@testable import sleight

final class PolyPadsARTests: XCTestCase {
    private var pads: PolyPads!

    override func setUp() {
        pads = PolyPads()
        pads.padCount = 12
        pads.root = 60
        pads.octaves = 2
        pads.scale = .minorPentatonic
        pads.padLayout = ARPadLayout.compute(padCount: 12)
        pads.padNotes = ARPadLayout.padNotes(padCount: 12, scale: .minorPentatonic, root: 60, octaves: 2)
    }

    /// Build a right hand with a specific finger's tip at (x, y).
    /// Other fingers are placed far from any pad.
    private func rightHand(finger: Int, tipX: Double, tipY: Double) -> HandFrame {
        var pts: [LandmarkPoint] = []
        for i in 0..<21 {
            let y: Double
            let x: Double
            switch i {
            case 0:  y = 0.9; x = 0.5     // wrist below pad area
            case 8, 12, 16, 20:  // finger tips
                if i == finger {
                    y = tipY; x = tipX
                } else {
                    y = 0.9; x = 0.3  // other fingers outside pad zone
                }
            case 5, 9, 13, 17:  // MCPs
                y = 0.85; x = 0.5
            default:
                y = 0.85; x = 0.5
            }
            pts.append(LandmarkPoint(x: x, y: y, confidence: 1.0))
        }
        return HandFrame(side: .right, points: pts, timestamp: 0)
    }

    // MARK: Air-tap press detection

    func testFingerInsidePadPlaysNote() {
        guard let pad0 = pads.padLayout?.first else { XCTFail("no layout"); return }
        let hand = rightHand(finger: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY))
        let evs = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertEqual(noteOns.count, 1, "finger inside pad should trigger one note")
        if case .noteOn(let n, _, _) = noteOns.first!.kind {
            XCTAssertEqual(n, pads.padNotes![0], "note should match pad 0's pre-computed note")
        }
    }

    func testFingerOutsidePadDoesNotPlay() {
        let hand = rightHand(finger: 8, tipX: 0.3, tipY: 0.5)
        let evs = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertTrue(noteOns.isEmpty, "finger outside any pad should not trigger a note")
    }

    func testFingerLeavingPadSendsNoteOff() {
        guard let pad0 = pads.padLayout?.first else { XCTFail("no layout"); return }
        // First tick: finger inside pad
        let pressHand = rightHand(finger: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY))
        _ = pads.update(hands: [pressHand], dt: 0.016)

        // Second tick: finger moves outside pad
        let releaseHand = rightHand(finger: 8, tipX: 0.3, tipY: 0.5)
        let evs = pads.update(hands: [releaseHand], dt: 0.016)
        let noteOffs = evs.filter { if case .noteOff = $0.kind { return true } else { return false } }
        XCTAssertFalse(noteOffs.isEmpty, "finger leaving pad should send note-off")
    }

    func testFingerStayingInPadDoesNotRetrigger() {
        guard let pad0 = pads.padLayout?.first else { XCTFail("no layout"); return }
        let hand = rightHand(finger: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY))
        _ = pads.update(hands: [hand], dt: 0.016)

        // Second tick: same position — should NOT produce another noteOn
        let evs2 = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs2.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertTrue(noteOns.isEmpty, "staying in same pad should not re-trigger note")
    }

    func testHandLostSendsAllNoteOffs() {
        guard let pad0 = pads.padLayout?.first else { XCTFail("no layout"); return }
        let pressHand = rightHand(finger: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY))
        _ = pads.update(hands: [pressHand], dt: 0.016)

        let evs = pads.update(hands: [], dt: 0.016)
        let noteOffs = evs.filter { if case .noteOff = $0.kind { return true } else { return false } }
        XCTAssertEqual(noteOffs.count, 1, "hand lost should send one note-off")
    }

    func testTwoFingersPlayTwoPads() {
        guard pads.padLayout!.count >= 2 else { XCTFail("need 2 pads"); return }
        let pad0 = pads.padLayout![0]
        let pad1 = pads.padLayout![1]

        var pts: [LandmarkPoint] = []
        for i in 0..<21 {
            let y: Double
            let x: Double
            switch i {
            case 0: y = 0.9; x = 0.5
            case 8:  y = Double(pad0.midY); x = Double(pad0.midX)  // index in pad 0
            case 12: y = Double(pad1.midY); x = Double(pad1.midX) // middle in pad 1
            case 16, 20: y = 0.9; x = 0.3  // other fingers away
            case 5, 9, 13, 17: y = 0.85; x = 0.5
            default: y = 0.85; x = 0.5
            }
            pts.append(LandmarkPoint(x: x, y: y, confidence: 1.0))
        }
        let hand = HandFrame(side: .right, points: pts, timestamp: 0)
        let evs = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertEqual(noteOns.count, 2, "two fingers in two pads should play two notes")
    }

    func testFingerMovingBetweenPadsReleasesFirst() {
        guard pads.padLayout!.count >= 2 else { XCTFail("need 2 pads"); return }
        let pad0 = pads.padLayout![0]
        let pad1 = pads.padLayout![1]

        // Press pad 0
        let hand0 = rightHand(finger: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY))
        _ = pads.update(hands: [hand0], dt: 0.016)

        // Move finger to pad 1
        let hand1 = rightHand(finger: 8, tipX: Double(pad1.midX), tipY: Double(pad1.midY))
        let evs = pads.update(hands: [hand1], dt: 0.016)
        let noteOffs = evs.filter { if case .noteOff = $0.kind { return true } else { return false } }
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertFalse(noteOffs.isEmpty, "moving to a new pad should release the old note")
        XCTAssertFalse(noteOns.isEmpty, "moving to a new pad should trigger the new note")
    }

    // MARK: Legacy extension mode (no pads)

    func testPadLayoutNilUsesExtensionMode() {
        pads.padLayout = nil
        pads.padNotes = nil
        pads.voiceCount = 4
        // Extended finger should produce a note (legacy mode)
        var pts: [LandmarkPoint] = []
        for i in 0..<21 {
            let y: Double
            switch i {
            case 0: y = 0.7
            case 8: y = 0.6
            case 5: y = 0.5
            default: y = 0.5
            }
            pts.append(LandmarkPoint(x: 0.5, y: y, confidence: 1.0))
        }
        let hand = HandFrame(side: .right, points: pts, timestamp: 0)
        let evs = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertFalse(noteOns.isEmpty, "extension mode should produce a note when finger is extended")
    }

    // MARK: Default settings + instrument switch

    @MainActor
    func testARPadsOnByDefaultForPolyPads() {
        let settings = AppSettings()
        XCTAssertTrue(settings.arPadsEnabled, "arPadsEnabled must default to true")

        settings.instrumentRaw = InstrumentType.polyPads.rawValue
        let controller = SleightController()
        controller.settings.instrumentRaw = InstrumentType.polyPads.rawValue
        controller.settings.arPadsEnabled = true
        controller.applySettings()

        guard let polyPads = controller.pipeline.instrument as? PolyPads else {
            XCTFail("expected PolyPads"); return
        }
        XCTAssertNotNil(polyPads.padLayout, "PolyPads.padLayout must be set when arPadsEnabled")
        XCTAssertNotNil(polyPads.padNotes, "PolyPads.padNotes must be set when arPadsEnabled")
        XCTAssertEqual(polyPads.padLayout?.count, controller.settings.padCount)
        XCTAssertEqual(polyPads.padNotes?.count, controller.settings.padCount)
    }

    @MainActor
    func testPolyPadsGetsPadLayoutOnInstrumentSwitch() {
        let controller = SleightController()
        controller.settings.instrumentRaw = InstrumentType.theremin.rawValue
        controller.settings.arPadsEnabled = true
        controller.applySettings()
        XCTAssertFalse(controller.pipeline.instrument is PolyPads)

        controller.settings.instrumentRaw = InstrumentType.polyPads.rawValue
        controller.settings.padCount = 8
        controller.applySettings()

        guard let polyPads = controller.pipeline.instrument as? PolyPads else {
            XCTFail("should be PolyPads"); return
        }
        XCTAssertEqual(polyPads.padLayout?.count, 8)
        XCTAssertEqual(polyPads.padNotes?.count, 8)
    }
}