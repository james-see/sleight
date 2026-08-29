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
        XCTAssertTrue(evs.contains { if case .perNotePitchBendSemitones = $0.kind { return true }; return false })
        XCTAssertTrue(evs.contains { if case .cc(7, _) = $0.kind { return true }; return false })
    }

    /// Pinch tightness at articulation maps to note velocity: fully closed
    /// pinch → 1.0 (127), pinch just inside the on-threshold → soft but audible.
    func testPinchTightnessSetsVelocity() {
        let tight = Theremin()
        let evTight = tight.update(hands: [rightHand(x: 0.75, y: 0.5, pinchNorm: 0.0), leftHand(y: 0.4)], dt: 1/60)
        let vTight = evTight.compactMap { if case .noteOn(_, let v) = $0.kind { return v }; return nil }.first
        XCTAssertEqual(vTight ?? 0, 1.0, accuracy: 0.0001)

        let loose = Theremin()
        let evLoose = loose.update(hands: [rightHand(x: 0.75, y: 0.5, pinchNorm: 0.34), leftHand(y: 0.4)], dt: 1/60)
        let vLoose = evLoose.compactMap { if case .noteOn(_, let v) = $0.kind { return v }; return nil }.first
        XCTAssertNotNil(vLoose)
        // v1 bounds in 7-bit were >30 && <60 (actual 42); same band as Double.
        XCTAssertGreaterThan(vLoose!, Double(30) / 127)
        XCTAssertLessThan(vLoose!, Double(60) / 127)
    }

    func testVelocityHelperClampsOutOfRangeAmounts() {
        XCTAssertEqual(Theremin.velocity(pinchAmount: -0.5, onThreshold: 0.35), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Theremin.velocity(pinchAmount: 1.0, onThreshold: 0.35), Double(40) / 127, accuracy: 0.0001)
        XCTAssertEqual(Theremin.velocity(pinchAmount: 0.2, onThreshold: 0), 1.0, accuracy: 0.0001)
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

    // ---- glide (v2) ----

    /// While gliding, crossing many scale tones must NOT re-articulate:
    /// one noteOn, continuous per-note bends, no noteOff in between.
    func testGlideHoldsSingleNoteAcrossScaleTones() {
        let t = Theremin()
        t.glideMode = .glide
        _ = t.update(hands: [rightHand(x: 0.56, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)], dt: 1/60)
        XCTAssertTrue(t.isGateOpen)
        var noteOns = 0, noteOffs = 0
        for x in stride(from: 0.57, through: 0.94, by: 0.01) {
            let evs = t.update(hands: [rightHand(x: x, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)], dt: 1/60)
            noteOns += evs.filter { if case .noteOn = $0.kind { return true }; return false }.count
            noteOffs += evs.filter { if case .noteOff = $0.kind { return true }; return false }.count
            let bend = evs.compactMap { if case .perNotePitchBendSemitones(let n, _) = $0.kind { return n }; return nil }.first
            XCTAssertNotNil(bend, "glide must keep streaming per-note bend")
        }
        XCTAssertLessThanOrEqual(noteOns, 1)
        XCTAssertEqual(noteOffs, 0)
    }

    /// Articulation still snaps to the nearest scale tone (scale decides where
    /// you land); while gliding the bend tracks the RAW hand position.
    func testGlideBendFollowsRawPitchNotQuantized() {
        let t = Theremin()
        t.glideMode = .glide
        t.octaves = 2
        _ = t.update(hands: [rightHand(x: 0.75, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)], dt: 1/60)
        let held = t.currentNote!
        // move well past a semitone without crossing a quantized tone boundary
        let evs = t.update(hands: [rightHand(x: 0.80, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)], dt: 1/60)
        let bend = evs.compactMap { if case .perNotePitchBendSemitones(let n, let s) = $0.kind { return (n, s) }; return nil }.first
        XCTAssertNotNil(bend)
        XCTAssertEqual(bend!.0, held)
        XCTAssertTrue(evs.allSatisfy { if case .noteOn = $0.kind { return false }; return true })
    }

    /// Gate close in glide mode: noteOff + bend-center reset, and NO cc7=0
    /// (volume is held, not floored — one-handed re-pinch keeps the level).
    func testGateCloseEmitsBendResetAndKeepsVolume() {
        let t = Theremin()
        t.glideMode = .glide
        _ = t.update(hands: [rightHand(x: 0.75, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)], dt: 1/60)
        let held = t.currentNote!
        let evs = t.update(hands: [rightHand(x: 0.75, y: 0.5, pinchNorm: 0.9), leftHand(y: 0.4)], dt: 1/60)
        XCTAssertEqual(evs.filter { if case .noteOff(let n) = $0.kind { return n == held }; return false }.count, 1)
        let reset = evs.compactMap { if case .perNotePitchBendSemitones(let n, let s) = $0.kind, n == held { return s }; return nil }.last
        XCTAssertEqual(reset ?? 1, 0, accuracy: 0.0001)   // bend centered
        XCTAssertFalse(evs.contains { if case .cc(7, 0) = $0.kind { return true }; return false })
    }

    /// Step mode keeps exact v1 re-articulation semantics.
    func testSteppedModeRetriggersOnToneCrossing() {
        let t = Theremin()
        t.glideMode = .stepped
        t.octaves = 2
        _ = t.update(hands: [rightHand(x: 0.56, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)], dt: 1/60)
        var articulations = 0
        for x in stride(from: 0.57, through: 0.94, by: 0.01) {
            let evs = t.update(hands: [rightHand(x: x, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)], dt: 1/60)
            articulations += evs.filter { if case .noteOn = $0.kind { return true }; return false }.count
        }
        XCTAssertGreaterThan(articulations, 8)   // pentatonic steps crossed
    }

    /// Spec §4.4: the sender-side clamp lives in the ENCODER, not the
    /// instrument. Extreme raw offsets at the band edges must saturate the
    /// wire word (full-scale bend), never wrap — Theremin emits unclamped and
    /// the encoder folds it. This pins the composed pipeline: a hand jump
    /// across the full 2-octave band produces a bend beyond the band span
    /// (vibrato transient rides on top), and the encoder word is full-scale.
    func testGlideExcursionAtBandEdgeSaturatesInEncoder() {
        let t = Theremin()
        t.glideMode = .glide
        t.octaves = 2
        _ = t.update(hands: [rightHand(x: 0.55, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)], dt: 1/60)
        let evs = t.update(hands: [rightHand(x: 0.95, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)], dt: 1/60)
        let bend = evs.compactMap { if case .perNotePitchBendSemitones(_, let s) = $0.kind { return s }; return nil }.first
        XCTAssertNotNil(bend)
        XCTAssertGreaterThan(bend!, 24.0)   // raw span + vibrato transient exceeds the bend range
        var enc = UMPEncoder(mode: .ump, userBendRange: 2, glide: true)
        enc.octaveSpanSemitones = t.octaves * 12
        let word = enc.encode(MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, bend!), timestamp: 0))[1]
        XCTAssertEqual(word, 0xFFFF_FFFF)   // encoder folds it to full-scale, no wraparound
    }
}