import XCTest
import CoreMIDI
@testable import sleight

final class UMPEncoderTests: XCTestCase {
    private func ump() -> UMPEncoder { UMPEncoder(mode: .ump, userBendRange: 2, glide: false) }
    private func mpe() -> UMPEncoder { UMPEncoder(mode: .mpe, userBendRange: 2, glide: false) }
    private func legacy() -> UMPEncoder { UMPEncoder(mode: .legacy, userBendRange: 2, glide: false) }

    // MARK: UMP mode (MIDI 2.0, 64-bit messages, ch1 = nibble 0)

    func testUMPNoteOn16BitVelocity() {
        // MIDI2NoteOn(0,0,60,0,0,65535): word0 = 0x4<<28|0x90<<16|60<<8 = 0x40903C00
        let w = ump().encode(MIDIEvent(kind: .noteOn(note: 60, velocity: 1.0), timestamp: 0))
        XCTAssertEqual(w, [0x4090_3C00, 0xFFFF_0000])
    }

    func testUMPNoteOnZeroVelocity() {
        let w = ump().encode(MIDIEvent(kind: .noteOn(note: 60, velocity: 0.0), timestamp: 0))
        XCTAssertEqual(w, [0x4090_3C00, 0x0000_0000])
    }

    func testUMPNoteOff() {
        let w = ump().encode(MIDIEvent(kind: .noteOff(note: 61), timestamp: 0))
        XCTAssertEqual(w, [0x4080_3D00, 0])
    }

    func testUMPPerNoteBendCenterIsNoBendWord() {
        let w = ump().encode(MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 0.0), timestamp: 0))
        // MIDI2PerNotePitchBend(0,0,60,0x80000000)
        XCTAssertEqual(w, [0x4060_3C00, 0x8000_0000])
    }

    func testUMPPerNoteBendPlusOneSemitoneOf24() {
        var enc = ump()
        enc.octaveSpanSemitones = 24
        enc.glide = true   // UMP glide range = ceil(24/12)*12 = 24
        let w = enc.encode(MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 1.0), timestamp: 0))
        // 0x80000000 + round(2^31/24) = 0x80000000 + 89478485
        XCTAssertEqual(w[0], 0x4060_3C00)
        XCTAssertEqual(w[1], UInt32(0x8000_0000) &+ 89_478_485)
    }

    func testUMPPerNoteBendClampsToRange() {
        var enc = UMPEncoder(mode: .ump, userBendRange: 2, glide: true)
        enc.octaveSpanSemitones = 24
        let up = enc.encode(MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 36.0), timestamp: 0))
        XCTAssertEqual(up[1], 0xFFFF_FFFF)   // clamped to +range
        let down = enc.encode(MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, -36.0), timestamp: 0))
        XCTAssertEqual(down[1], 1)           // one step in from the raw extreme (standard asymmetry)
    }

    func testUMPCC7IsLeftShifted25() {
        let w = ump().encode(MIDIEvent(kind: .cc(7, 64), timestamp: 0))
        XCTAssertEqual(w, [0x40B0_0700, 64 << 25])
    }

    func testUMPBendRangeSetupSelectThenDataEntry() {
        var enc = ump()
        enc.octaveSpanSemitones = 24
        enc.glide = true
        let w = enc.bendRangeSetupWords()
        // Six 2-word MIDI 2.0 CC messages (12 words total):
        // select (CC101=0, CC100=0) → data entry (CC6=r, CC38=0) → null (101/100=127)
        XCTAssertEqual(w.count, 12)
        XCTAssertEqual(w[0], 0x40B0_6500);  XCTAssertEqual(w[1], 0)         // CC101 = 0 (RPN msb)
        XCTAssertEqual(w[2], 0x40B0_6400);  XCTAssertEqual(w[3], 0)         // CC100 = 0 (RPN lsb)
        XCTAssertEqual(w[4], 0x40B0_0600);  XCTAssertEqual(w[5], 24 << 25)  // CC6 data = ±24 semis
        XCTAssertEqual(w[6], 0x40B0_2600);  XCTAssertEqual(w[7], 0)         // CC38 = 0
        XCTAssertEqual(w[8], 0x40B0_6500);  XCTAssertEqual(w[9], 127 << 25) // RPN null
        XCTAssertEqual(w[10], 0x40B0_6400); XCTAssertEqual(w[11], 127 << 25)
    }

    // MARK: MPE mode (MIDI 1.0 words; notes + bend on nibble 1 = ch 2)

    func testMPENoteOnUsesChannel2Nibble() {
        // byte1 = 0x91 (ch index 1); velocity 127 for 1.0
        let w = mpe().encode(MIDIEvent(kind: .noteOn(note: 60, velocity: 1.0, channel: 1), timestamp: 0))
        XCTAssertEqual(w, [0x2091_3C7F])
    }

    func testMPEPerNoteBendRange48() {
        // +1 semitone of ±48 → 8192 + round(8191/48) = 8192 + 171 = 8363 = 0x20AB
        // → lsb 0x2B msb 0x41 → data 0x412B
        let w = mpe().encode(MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 1.0, channel: 1), timestamp: 0))
        XCTAssertEqual(w, [0x20E1_412B])   // bend on ch2 (byte1 0xE1), lsb|msb<<8
    }

    func testMPECCStaysOnChannel1() {
        let w = mpe().encode(MIDIEvent(kind: .cc(7, 64), timestamp: 0))
        XCTAssertEqual(w, [0x20B0_0740])
    }

    func testMPEInitWordsList() {
        let w = mpe().bendRangeSetupWords()
        // MPE configuration (RPN 0006, data = 1 member channel → ch 2) then
        // bend range (RPN 0000, data = 48) — each frame closed with RPN null.
        // All on channel-1 MIDI1 words.
        XCTAssertEqual(w, [
            0x20B0_6500, 0x20B0_6406, 0x20B0_0601, 0x20B0_657F, 0x20B0_647F, // MPE config, 1 member
            0x20B0_6500, 0x20B0_6400, 0x20B0_0630, 0x20B0_657F, 0x20B0_647F, // bend range 48
        ])
    }

    // MARK: Legacy mode (v1 byte-compat via MIDI1 UMP words, ch1 = nibble 0)

    func testLegacyNoteOnMatchesV1Bytes() {
        // [0x90, 60, 100] as MIDI1 UMP word 0x2<<28|0x90<<16|0x3C<<8|0x64
        let w = legacy().encode(MIDIEvent(kind: .noteOn(note: 60, velocity: Double(100) / 127), timestamp: 0))
        XCTAssertEqual(w, [0x2090_3C64])
    }

    func testLegacyBendCenterAndClampMatchV1() {
        XCTAssertEqual(legacy().encode(MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 0.0), timestamp: 0)), [0x20E0_4000])
        XCTAssertEqual(legacy().encode(MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 5.0), timestamp: 0)), [0x20E0_7F7F])
    }

    func testLegacySetupWordsEmpty() {
        XCTAssertTrue(legacy().bendRangeSetupWords().isEmpty)
    }

    func testProtocolIDAndWordsPerEvent() {
        XCTAssertEqual(ump().protocolID, MIDIProtocolID(rawValue: 2)!)
        XCTAssertEqual(mpe().protocolID, MIDIProtocolID(rawValue: 1)!)
        XCTAssertEqual(legacy().wordsPerEvent, 1)
        XCTAssertEqual(ump().wordsPerEvent, 2)
    }

    func testMPENoteOnUsesExplicitChannel() {
        let enc = UMPEncoder(mode: .mpe, userBendRange: 2, glide: false)
        let e = MIDIEvent(kind: .noteOn(note: 60, velocity: 1.0, channel: 3), timestamp: 0)
        let words = enc.encode(e)
        XCTAssertEqual(words.count, 1)
        let channelNibble = (words[0] >> 16) & 0xF
        XCTAssertEqual(channelNibble, 3)
    }

    func testLegacyUsesEventChannel() {
        let enc = UMPEncoder(mode: .legacy, userBendRange: 2, glide: false)
        let e = MIDIEvent(kind: .noteOn(note: 60, velocity: 1.0, channel: 5), timestamp: 0)
        let words = enc.encode(e)
        let channelNibble = (words[0] >> 16) & 0xF
        XCTAssertEqual(channelNibble, 5)
    }

    func testUMPModeIgnoresEventChannel() {
        let enc = UMPEncoder(mode: .ump, userBendRange: 2, glide: false)
        let e = MIDIEvent(kind: .noteOn(note: 60, velocity: 1.0, channel: 7), timestamp: 0)
        let words = enc.encode(e)
        let channelNibble = (words[0] >> 16) & 0xF
        XCTAssertEqual(channelNibble, 0)
    }
}