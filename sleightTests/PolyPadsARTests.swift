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
        pads.pressThreshold = 0.30
        pads.releaseThreshold = 0.38
    }

    /// Build a right hand with a specific finger's tip at (x, y) and a given
    /// extension ratio (distance tip-to-MCP / palmSize). Low extension = curled.
    /// The target finger's MCP is placed directly below the tip at the correct
    /// distance to achieve the desired extension ratio.
    private func rightHand(finger: Int, tipX: Double, tipY: Double, extensionRatio: Double) -> HandFrame {
        // Fixed palm geometry: wrist and middleMCP are always the same,
        // so palmSize is constant across all tests.
        let wristY = 0.95
        let middleMCPY = 0.85
        let palmSize = wristY - middleMCPY  // 0.10

        // Target finger's MCP: directly below tip at the right distance
        let tipMcpDist = extensionRatio * palmSize
        let targetMCPY = tipY + tipMcpDist  // MCP below tip (higher Y = lower on screen)

        var pts: [LandmarkPoint] = []
        for i in 0..<21 {
            let y: Double
            let x: Double
            switch i {
            case 0:  // wrist
                y = wristY; x = 0.5
            case 8, 12, 16, 20:  // finger tips
                if i == finger {
                    y = tipY; x = tipX
                } else {
                    // Other fingers: extended and away from pads
                    y = middleMCPY - 0.06; x = 0.3
                }
            case 5, 9, 13, 17:  // MCPs
                if i == finger - 3 {  // the MCP for the target finger (tip-3 = MCP)
                    y = targetMCPY; x = tipX
                } else {
                    y = middleMCPY; x = 0.5
                }
            default:
                y = middleMCPY; x = 0.5
            }
            pts.append(LandmarkPoint(x: x, y: y, confidence: 1.0))
        }
        return HandFrame(side: .right, points: pts, timestamp: 0)
    }

    // MARK: Curl-gate press detection

    func testFlatHandOverPadDoesNotPlay() {
        // Finger inside pad rect but extended (flat hand) — should NOT play
        guard let pad0 = pads.padLayout?.first else { XCTFail("no layout"); return }
        let hand = rightHand(finger: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY), extensionRatio: 0.50)
        let evs = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertTrue(noteOns.isEmpty, "flat hand (extended) over pad should NOT trigger a note")
    }

    func testCurlFingerInsidePadPlaysNote() {
        // Finger inside pad rect AND curled — should play
        guard let pad0 = pads.padLayout?.first else { XCTFail("no layout"); return }
        let hand = rightHand(finger: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY), extensionRatio: 0.15)
        let evs = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertEqual(noteOns.count, 1, "curled finger inside pad should trigger one note")
        if case .noteOn(let n, _, _) = noteOns.first!.kind {
            XCTAssertEqual(n, pads.padNotes![0], "note should match pad 0's pre-computed note")
        }
    }

    func testCurlFingerOutsidePadDoesNotPlay() {
        // Finger curled but NOT inside any pad rect — no note
        let hand = rightHand(finger: 8, tipX: 0.3, tipY: 0.5, extensionRatio: 0.15)
        let evs = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertTrue(noteOns.isEmpty, "curled finger outside any pad should not trigger a note")
    }

    func testExtendingFingerReleasesNote() {
        guard let pad0 = pads.padLayout?.first else { XCTFail("no layout"); return }
        // Press: curled inside pad
        let pressHand = rightHand(finger: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY), extensionRatio: 0.15)
        _ = pads.update(hands: [pressHand], dt: 0.016)
        // Release: extend finger (still inside pad, but now flat)
        let releaseHand = rightHand(finger: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY), extensionRatio: 0.50)
        let evs = pads.update(hands: [releaseHand], dt: 0.016)
        let noteOffs = evs.filter { if case .noteOff = $0.kind { return true } else { return false } }
        XCTAssertFalse(noteOffs.isEmpty, "extending finger should release the note")
    }

    func testFingerLeavingPadSendsNoteOff() {
        guard let pad0 = pads.padLayout?.first else { XCTFail("no layout"); return }
        let pressHand = rightHand(finger: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY), extensionRatio: 0.15)
        _ = pads.update(hands: [pressHand], dt: 0.016)
        // Move finger outside pad (still curled)
        let releaseHand = rightHand(finger: 8, tipX: 0.3, tipY: 0.5, extensionRatio: 0.15)
        let evs = pads.update(hands: [releaseHand], dt: 0.016)
        let noteOffs = evs.filter { if case .noteOff = $0.kind { return true } else { return false } }
        XCTAssertFalse(noteOffs.isEmpty, "finger leaving pad should send note-off")
    }

    func testStayingCurledInPadDoesNotRetrigger() {
        guard let pad0 = pads.padLayout?.first else { XCTFail("no layout"); return }
        let hand = rightHand(finger: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY), extensionRatio: 0.15)
        _ = pads.update(hands: [hand], dt: 0.016)
        let evs2 = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs2.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertTrue(noteOns.isEmpty, "staying curled in same pad should not re-trigger note")
    }

    func testHandLostSendsAllNoteOffs() {
        guard let pad0 = pads.padLayout?.first else { XCTFail("no layout"); return }
        let pressHand = rightHand(finger: 8, tipX: Double(pad0.midX), tipY: Double(pad0.midY), extensionRatio: 0.15)
        _ = pads.update(hands: [pressHand], dt: 0.016)
        let evs = pads.update(hands: [], dt: 0.016)
        let noteOffs = evs.filter { if case .noteOff = $0.kind { return true } else { return false } }
        XCTAssertEqual(noteOffs.count, 1, "hand lost should send one note-off")
    }

    func testTwoCurlFingersPlayTwoPads() {
        guard pads.padLayout!.count >= 2 else { XCTFail("need 2 pads"); return }
        let pad0 = pads.padLayout![0]
        let pad1 = pads.padLayout![1]
        let palmSize = 0.10
        let tipMcpDist = 0.15 * palmSize  // curled

        var pts: [LandmarkPoint] = []
        for i in 0..<21 {
            let y: Double
            let x: Double
            switch i {
            case 0: y = 0.95; x = 0.5
            case 8:  y = Double(pad0.midY); x = Double(pad0.midX)
            case 12: y = Double(pad1.midY); x = Double(pad1.midX)
            case 5:  y = Double(pad0.midY) + tipMcpDist; x = Double(pad0.midX)  // index MCP
            case 9:  y = Double(pad1.midY) + tipMcpDist; x = Double(pad1.midX)  // middle MCP
            case 13, 17: y = 0.85; x = 0.5  // other MCPs (not used)
            case 16, 20: y = 0.85 - 0.06; x = 0.3  // other fingers away
            default: y = 0.85; x = 0.5
            }
            pts.append(LandmarkPoint(x: x, y: y, confidence: 1.0))
        }
        let hand = HandFrame(side: .right, points: pts, timestamp: 0)
        let evs = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertEqual(noteOns.count, 2, "two curled fingers in two pads should play two notes")
    }

    // MARK: Legacy extension mode (no pads)

    func testPadLayoutNilUsesExtensionMode() {
        pads.padLayout = nil
        pads.padNotes = nil
        pads.voiceCount = 4
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