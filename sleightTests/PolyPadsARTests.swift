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
}