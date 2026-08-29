import XCTest
@testable import sleight

final class PolyPadsTests: XCTestCase {
    private var pads: PolyPads!

    override func setUp() {
        pads = PolyPads()
        pads.voiceCount = 4
        pads.root = 60
        pads.octaves = 1
        pads.scale = .chromatic
    }

    // MARK: Helpers — build a HandFrame with 4 extended fingers

    private func rightHand(yPositions: [Double]) -> HandFrame {
        var pts: [LandmarkPoint] = []
        for i in 0..<21 {
            let y: Double
            switch i {
            case 0:  y = 0.7          // wrist — separated from MCPs for realistic palm size
            case 8:  y = yPositions[0]   // index tip
            case 12: y = yPositions[1]   // middle tip
            case 16: y = yPositions[2]   // ring tip
            case 20: y = yPositions[3]   // little tip
            case 5, 9, 13, 17: y = 0.5  // MCPs (mid-range)
            default: y = 0.5
            }
            pts.append(LandmarkPoint(x: 0.5, y: y, confidence: 1.0))
        }
        return HandFrame(side: .right, points: pts, timestamp: 0)
    }

    // MARK: Note generation

    func testFourExtendedFingersProduceFourNoteOns() {
        let hand = rightHand(yPositions: [0.6, 0.7, 0.8, 0.9]) // spread across band
        let evs = pads.update(hands: [hand], dt: 0.016)
        let noteOns = evs.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertEqual(noteOns.count, 4)
        // Distinct notes (chromatic scale, different Y values)
        let notes = Set(noteOns.compactMap { e -> UInt8? in
            if case .noteOn(let n, _, _) = e.kind { return n }
            return nil
        })
        XCTAssertEqual(notes.count, 4)
    }

    func testEachNoteOnHasDistinctChannel() {
        let hand = rightHand(yPositions: [0.6, 0.7, 0.8, 0.9])
        let evs = pads.update(hands: [hand], dt: 0.016)
        let channels = evs.compactMap { e -> UInt8? in
            if case .noteOn(_, _, let ch) = e.kind { return ch }
            return nil
        }
        XCTAssertEqual(Set(channels).count, 4)
        XCTAssertTrue(channels.allSatisfy { $0 >= 1 && $0 <= 4 })
    }

    func testRetractingOneFingerSendsOnlyItsNoteOff() {
        // First tick: all 4 extended
        let hand1 = rightHand(yPositions: [0.6, 0.7, 0.8, 0.9])
        _ = pads.update(hands: [hand1], dt: 0.016)

        // Second tick: retract index finger (y above band = effectively retracted, or just different y)
        // Simulate by making index finger tip very close to MCP
        var pts = hand1.points
        pts[8] = LandmarkPoint(x: 0.5, y: 0.51, confidence: 1.0) // index tip near MCP → short distance → not extended
        let hand2 = HandFrame(side: .right, points: pts, timestamp: 0.016)
        let evs2 = pads.update(hands: [hand2], dt: 0.016)
        let noteOffs = evs2.filter { if case .noteOff = $0.kind { return true } else { return false } }
        XCTAssertEqual(noteOffs.count, 1)
        if case .noteOff(let n, _) = noteOffs.first!.kind {
            XCTAssertNotNil(n)
        }
    }

    func testRightHandLostSendsAllNoteOffs() {
        let hand = rightHand(yPositions: [0.6, 0.7, 0.8, 0.9])
        _ = pads.update(hands: [hand], dt: 0.016)
        let evs = pads.update(hands: [], dt: 0.016) // no hands
        let noteOffs = evs.filter { if case .noteOff = $0.kind { return true } else { return false } }
        XCTAssertEqual(noteOffs.count, 4)
    }

    func testHeldFingerEmitsPerNoteBend() {
        let hand = rightHand(yPositions: [0.6, 0.6, 0.6, 0.6])
        let evs1 = pads.update(hands: [hand], dt: 0.016)
        let noteOns1 = evs1.filter { if case .noteOn = $0.kind { return true } else { return false } }
        XCTAssertEqual(noteOns1.count, 4)

        // Second tick: same hand (still extended) → should get bend events
        let evs2 = pads.update(hands: [hand], dt: 0.016)
        let bends = evs2.filter { if case .perNotePitchBendSemitones = $0.kind { return true } else { return false } }
        XCTAssertEqual(bends.count, 4)
    }

    func testLeftHandProducesCC7() {
        let right = rightHand(yPositions: [0.6, 0.7, 0.8, 0.9])
        var leftPts: [LandmarkPoint] = []
        for _ in 0..<21 { leftPts.append(LandmarkPoint(x: 0.5, y: 0.3, confidence: 1.0)) }
        let left = HandFrame(side: .left, points: leftPts, timestamp: 0)
        let evs = pads.update(hands: [right, left], dt: 0.016)
        let ccs = evs.filter { if case .cc(7, _) = $0.kind { return true } else { return false } }
        XCTAssertFalse(ccs.isEmpty)
    }
}
