import XCTest
@testable import sleight

/// Regression: MIDIEventListAdd corrupts the Swift heap on macOS 26.6
/// (proven: probes F1/F2/F3/G + ASan fault 0x100000008 — the exact faulting
/// address from the in-app crash). transmit() must hand-pack the MIDIEventList
/// without ever calling MIDIEventListAdd. This smoke drives the real send path
/// 600x; before the fix it dies in transmit, after it it returns cleanly.
final class MIDISourceTransmitSmokeTests: XCTestCase {
    func testTransmitManyBatchesSurvives() {
        let source = MIDISource(name: "SleightSmokeTest-\(getpid())")
        let now: Double = 1.0
        // Mixed batch shaped like a real pinch frame: on + bend + cc, then off.
        let batches: [[MIDIEvent]] = [
            [ MIDIEvent(kind: .noteOn(note: 60, velocity: 0.7), timestamp: now),
              MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 1.25), timestamp: now),
              MIDIEvent(kind: .cc(7, 90), timestamp: now) ],
            [ MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, -0.5), timestamp: now) ],
            [ MIDIEvent(kind: .noteOff(note: 60), timestamp: now) ],
        ]
        // UMP protocol transmit batch, then a protocol-1 recreate + legacy words.
        for _ in 0..<100 { for batch in batches { source.send(batch) } }
        source.configure(mode: .legacy, userBendRange: 2, octaveSpanSemitones: 2, glide: false)
        for _ in 0..<100 { for batch in batches { source.send(batch) } }

        // No crash reaching here = the regression signal. The pre-fix crash was
        // instantaneous inside the send path.
        XCTAssertEqual(source.mode, .legacy)
    }
}