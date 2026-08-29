# Sleight v2 (MIDI 2.0 + Glide) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace v1's MIDI 1.1 byte output with a three-mode protocol layer — UMP (MIDI 2.0, default), MPE, plain MIDI 1.1 — and add continuous glide while a pinched note is held.

**Architecture:** One `MIDIEventList` send path for all modes. A new pure `UMPEncoder` maps the existing `MIDIEvent` stream to per-mode UMP words (unit tests assert exact 32-bit words). `MIDISource` is recreated via `MIDISourceCreateWithProtocol` on mode change. Theremin gains a glide mode: articulation snaps to the quantized scale tone, then per-note bend carries raw hand pitch continuously (no re-articulation while held).

**Tech Stack:** Swift 5.10, CoreMIDI (`MIDIEventList`, `MIDISourceCreateWithProtocol`), XCTest, XcodeGen.

Spec: `docs/superpowers/specs/2026-08-28-sleight-v2-midi2-design.md`

## Global Constraints

- Build/test commands MUST use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (xcode-select points at CommandLineTools).
- Run `xcodegen generate` before building after any file is added/removed (project uses directory globs).
- macOS 14.0 deployment target, arm64 only, no third-party dependencies (unchanged from `project.yml`).
- UMP group = 0; human channel 1 = channel nibble **0** (v1 emitted `0x90` = ch1); MPE note channel = nibble **1** ("channel 2"); CC always nibble 0.
- v1 byte-compatibility vector for legacy mode: noteOn raw bytes `[0x90, note, vel]`, noteOff `[0x80, note, 0]`, CC `[0xB0, c, v]`, bend `8192 + round(clamp(s/r, -1, 1) * 8191)` little-endian 7-bit pairs, channel nibble 0.
- AppSettings pattern: `@Published` var + Combine sink persisting to UserDefaults (NOT `@AppStorage`) — see `sleight/Support/Settings.swift` header comment.
- Docs updated in the same PR as code; do not add new doc files; commit after every task.
- `scripts/setup-secrets.sh` has pre-existing local modifications — do not stage it.

---

### Task 1: Reshape `MIDIEvent.Kind` (per-note attribution, Double velocity)

**Files:**
- Modify: `sleight/Core/Types.swift`
- Modify: `sleight/Instruments/Theremin.swift`
- Modify: `sleight/MIDI/MIDISource.swift` (byte encoder ext only)
- Modify: `sleight/Synth/TestSynth.swift`
- Modify: `sleightTests/MIDIEventTests.swift`
- Modify: `sleightTests/ThereminTests.swift`

**Interfaces:**
- Produces: `MIDIEvent.Kind` = `.noteOn(note: UInt8, velocity: Double)`, `.noteOff(note: UInt8)`, `.perNotePitchBendSemitones(note: UInt8, Double)`, `.cc(UInt8, UInt8)` (velocity 0…1 final velocity; UMP 16-bit and 7-bit paths derive from it in Task 2).
- Produces: `Theremin.velocity(pinchAmount:onThreshold:) -> Double` (0…1; fully pinched = 1.0, at on-threshold = 40/127).
- Keep the legacy `MIDIEvent.encode(bendRangeSemitones:)` byte encoder this task so `MIDISource` stays byte-compatible until Task 3 swaps the send path.

- [ ] **Step 1: Update MIDIEventTests to the new Kind shapes (failing test)**

Replace `sleightTests/MIDIEventTests.swift` content with:

```swift
import XCTest
@testable import sleight

final class MIDIEventTests: XCTestCase {
    func testNoteOnEncoding() {
        let e = MIDIEvent(kind: .noteOn(note: 60, velocity: Double(100) / 127), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0x90, 60, 100])
    }

    func testNoteOffEncoding() {
        let e = MIDIEvent(kind: .noteOff(note: 60), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0x80, 60, 0])
    }

    // v1 semantics preserved: per-note bend still emits a channel bend (E0)
    // on the legacy path; note number is carried but unused until Task 2.
    func testPitchBendCenter() {
        let e = MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 0.0), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xE0, 0, 64]) // 8192 centered
    }

    func testPitchBendPositiveHalfRange() {
        // +1.0 semitone of ±2 → 8192 + round(0.5*8191) = 12288 → lsb 0, msb 96
        let e = MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 1.0), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xE0, 0, 96])
    }

    func testPitchBendClampsOutOfRange() {
        let e = MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 5.0), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xE0, 127, 127]) // 8192+8191
        let e2 = MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, -5.0), timestamp: 0)
        XCTAssertEqual(e2.encode(bendRangeSemitones: 2), [0xE0, 1, 0]) // 14-bit asymmetry
    }

    func testCC7Encoding() {
        let e = MIDIEvent(kind: .cc(7, 64), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xB0, 7, 64])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' build-for-testing 2>&1 | grep -E "error|BUILD" | head -20
```

Expected: FAIL — `Type 'MIDIEvent.Kind' has no member 'noteOn(note:velocity:)'` (old tuple label shape).

- [ ] **Step 3: Reshape `Kind` in `sleight/Core/Types.swift`**

```swift
public struct MIDIEvent: Equatable {
    public enum Kind: Equatable {
        case noteOn(note: UInt8, velocity: Double)          // velocity = final velocity 0…1
        case noteOff(note: UInt8)
        case perNotePitchBendSemitones(note: UInt8, Double) // bend attached to a sounding note
        case cc(UInt8, UInt8)                               // global, 0-127
    }
    public var kind: Kind
    public var timestamp: Double
    public init(kind: Kind, timestamp: Double) {
        self.kind = kind
        self.timestamp = timestamp
    }
}
```

- [ ] **Step 4: Update Theremin velocity + emission in `sleight/Instruments/Theremin.swift`**

Velocity helper becomes Double (same floor/closeness math, normalized by 127):

```swift
    /// Pinch tightness → note velocity as a 0…1 Double. `pinchAmount` is the
    /// normalized thumb/index distance (0 = fully pinched); amounts at or
    /// beyond the pinch on-threshold map to minVelocity/127, fully closed to 1.0.
    public static func velocity(pinchAmount: Double, onThreshold: Double) -> Double {
        guard onThreshold > 0 else { return 1.0 }
        let closeness = 1 - min(max(pinchAmount / onThreshold, 0), 1)
        return (Double(minVelocity) + closeness * Double(127 - minVelocity)) / 127.0
    }
```

Update the three emission sites (articulation ×2, held expression ×1):

```swift
        if wantGate {
            if !isGateOpen {
                isGateOpen = true
                currentNote = baseNote
                let vel = Self.velocity(pinchAmount: lastPinchAmount, onThreshold: pinch.onThreshold)
                events.append(MIDIEvent(kind: .noteOn(note: baseNote, velocity: vel), timestamp: t))
            } else if baseNote != currentNote {
                if let old = currentNote {
                    events.append(MIDIEvent(kind: .noteOff(note: old), timestamp: t))
                }
                currentNote = baseNote
                let vel = Self.velocity(pinchAmount: lastPinchAmount, onThreshold: pinch.onThreshold)
                events.append(MIDIEvent(kind: .noteOn(note: baseNote, velocity: vel), timestamp: t))
            }
            events.append(MIDIEvent(kind: .perNotePitchBendSemitones(note: baseNote, bendSemitones()), timestamp: t))
            events.append(MIDIEvent(kind: .cc(7, volume), timestamp: t))
        } else if isGateOpen {
            isGateOpen = false
            if let n = currentNote {
                events.append(MIDIEvent(kind: .noteOff(note: n), timestamp: t))
            }
            currentNote = nil
            events.append(MIDIEvent(kind: .cc(7, 0), timestamp: t))
            lastVolume = 0
        }
```

- [ ] **Step 5: Update legacy byte encoder in `sleight/MIDI/MIDISource.swift`** (keep bytes identical)

```swift
extension MIDIEvent {
    /// MIDI 1.1 channel-1 bytes (unchanged numbers; Double velocity rounds to 7-bit).
    public func encode(bendRangeSemitones: Double) -> [UInt8] {
        switch kind {
        case let .noteOn(note, velocity):
            let v = UInt8((min(max(velocity, 0), 1) * 127).rounded())
            return [0x90, note, v]
        case let .noteOff(note):
            return [0x80, note, 0]
        case let .cc(controller, value):
            return [0xB0, controller, value]
        case let .perNotePitchBendSemitones(_, semis):
            let clamped = min(max(semis / bendRangeSemitones, -1), 1)
            let v = 8192 + Int((clamped * 8191).rounded())
            return [0xE0, UInt8(v & 0x7F), UInt8((v >> 7) & 0x7F)]
        }
    }
}
```

- [ ] **Step 6: Update TestSynth `handle` in `sleight/Synth/TestSynth.swift`** (match statements only)

```swift
            case let .noteOn(note, _):
                baseFreq = 440.0 * pow(2, (Double(note) - 69) / 12)
                freq = baseFreq
                targetLevel = 0.18
                start()
            case .noteOff:
                targetLevel = 0
            case let .cc(7, value):
                if targetLevel > 0 { targetLevel = Float(value) / 127 * 0.4 }
            case let .perNotePitchBendSemitones(_, semis):
                freq = baseFreq * pow(2, semis / 12)
```

(`Synth/` synth feels glide when Task 4 lands because it consumes raw events.)

- [ ] **Step 7: Update ThereminTests** — velocity assertions become Double; note-On patterns:

In `testPinchTightnessSetsVelocity` replace velocity extraction:

```swift
        let vTight = evTight.compactMap { if case .noteOn(_, let v) = $0.kind { return v }; return nil }.first
        XCTAssertEqual(vTight ?? 0, 1.0, accuracy: 0.0001)
```

and

```swift
        let vLoose = evLoose.compactMap { if case .noteOn(_, let v) = $0.kind { return v }; return nil }.first
        XCTAssertNotNil(vLoose)
        XCTAssertGreaterThan(vLoose!, Double(45) / 127)   // v1 range 45..126 for pinchNorm 0.34
        XCTAssertLessThan(vLoose!, Double(60) / 127)
```

In `testVelocityHelperClampsOutOfRangeAmounts`:

```swift
        XCTAssertEqual(Theremin.velocity(pinchAmount: -0.5, onThreshold: 0.35), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Theremin.velocity(pinchAmount: 1.0, onThreshold: 0.35), Double(40) / 127, accuracy: 0.0001)
        XCTAssertEqual(Theremin.velocity(pinchAmount: 0.2, onThreshold: 0), 1.0, accuracy: 0.0001)
```

- [ ] **Step 8: Regenerate project (no new files, but harmless), build + run full tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: all existing tests PASS (no MIDI bytes changed yet).

- [ ] **Step 9: Commit**

```bash
git add sleight/Core/Types.swift sleight/Instruments/Theremin.swift sleight/MIDI/MIDISource.swift sleight/Synth/TestSynth.swift sleightTests/MIDIEventTests.swift sleightTests/ThereminTests.swift
git commit -m "refactor: per-note attribution + Double velocity in MIDIEvent.Kind"
```

---

### Task 2: `UMPEncoder` — pure per-mode word encoding

**Files:**
- Create: `sleight/MIDI/UMPEncoder.swift`
- Create: `sleightTests/UMPEncoderTests.swift`

**Interfaces:**
- Consumes: `MIDIEvent.Kind` shapes from Task 1.
- Produces: `MIDIMode { ump, mpe, legacy }`, `GlideMode { stepped, glide }`, and

```swift
public struct UMPEncoder {
    public init(mode: MIDIMode, userBendRange: Double, glide: Bool)
    public var protocolID: MIDIProtocolID      // .ump → kMIDIProtocol_2_0 else _1_0
    public var wordsPerEvent: Int              // 2 for .ump else 1
    public var bendRangeSemitones: Double      // ump: glide ? ceil(octaveSpan) : userBendRange
                                               // mpe: 48 · legacy: userBendRange
    public var octaveSpanSemitones: Double     // settable; default 24
    public func encode(_ event: MIDIEvent) -> [UInt32]
    public func bendRangeSetupWords() -> [UInt32]   // ump: RPN0 · mpe: init list · legacy: []
}
```

Word derivations (verified against `MIDIMessages.h` inline helpers: `MIDI2ChannelVoiceMessage` = `(group|0x40)<<24 | (channel|status<<4)<<16 | index`, NoteOn value = `velocity<<16`, per-note bend value 32-bit with 0x80000000 = center, CC value = `cc<<25`; `MIDI1UPChannelVoiceMessage` = `0x2<<28 | (channel|status<<4)<<16 | data1<<8 | data2`):

- [ ] **Step 1: Write failing word-level tests in `sleightTests/UMPEncoderTests.swift`**

```swift
import XCTest
import CoreMIDI
@testable import sleight

final class UMPEncoderTests: XCTestCase {
    private func ump() -> UMPEncoder { UMPEncoder(mode: .ump, userBendRange: 2, glide: false) }
    private func mpe() -> UMPEncoder { UMPEncoder(mode: .mpe, userBendRange: 2, glide: false) }
    private func legacy() -> UMPEncoder { UMPEncoder(mode: .legacy, userBendRange: 2, glide: false) }

    // MARK: UMP mode

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
        XCTAssertEqual(up[1], 0xFFFF_FFFF)                    // clamp to +range
        let down = enc.encode(MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, -36.0), timestamp: 0))
        XCTAssertEqual(down[1], 1)                            // 14/32-bit asymmetry: one step in
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
        // select (CC101=0, CC100=0) → data entry (CC6=r, CC38=0) → null (101/100=127)
        XCTAssertEqual(w.count, 6)
        XCTAssertEqual(w[0], [0x40B0_6500, 0])          // CC101 msb = 0 (RPN 0)
        XCTAssertEqual(w[1], [0x40B0_6400, 0])          // CC100 lsb = 0
        XCTAssertEqual(w[2], [0x40B0_0600, 24 << 25])   // CC6 data = 24 semis
        XCTAssertEqual(w[3], [0x40B0_2600, 0])         // CC38 lsb = 0
        XCTAssertEqual(w[4], [0x40B0_6500, 127 << 25]) // RPN null
        XCTAssertEqual(w[5], [0x40B0_6400, 127 << 25])
    }

    // MARK: MPE mode

    func testMPENoteOnUsesChannel2Nibble() {
        // byte1 = 0x91 (ch index 1); velocity 127 for 1.0
        let w = mpe().encode(MIDIEvent(kind: .noteOn(note: 60, velocity: 1.0), timestamp: 0))
        XCTAssertEqual(w, [0x2091_3C7F])
    }

    func testMPEPerNoteBendRange48() {
        // +1 semitone of ±48 → 8192 + round(8191/48)=8192+171=8363 → lsb 0x2B msb 0x41
        let w = mpe().encode(MIDIEvent(kind: .perNotePitchBendSemitones(note: 60, 1.0), timestamp: 0))
        XCTAssertEqual(w, [0x20E1_412B])   // bend on ch2 (byte1 0xE1), lsb|msb<<8
    }

    func testMPECCStaysOnChannel1() {
        let w = mpe().encode(MIDIEvent(kind: .cc(7, 64), timestamp: 0))
        XCTAssertEqual(w, [0x20B0_0740])
    }

    func testMPEInitWordsList() {
        let w = mpe().bendRangeSetupWords()
        // MPE config RPN6 (msb 0, lsb 1) + data entry, RPN nulls; then bend range
        // RPN0 (msb 48) + data entry + nulls. All on channel-1 MIDI1 words.
        XCTAssertEqual(w, [
            0x20B0_6500, 0x20B0_6400, 0x20B0_0600 | 1, 0x20B0_2600, // RPN 6, MPE members = 1
            0x20B0_657F, 0x20B0_647F,                               // null
            0x20B0_6500, 0x20B0_6400, 0x20B0_0630, 0x20B0_2600,     // RPN 0, data = 48
            0x20B0_657F, 0x20B0_647F,                               // null
        ])
    }

    // MARK: Legacy mode (v1 byte-compat)

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
        XCTAssertEqual(ump().protocolID, kMIDIProtocol_2_0)
        XCTAssertEqual(mpe().protocolID, kMIDIProtocol_1_0)
        XCTAssertEqual(legacy().wordsPerEvent, 1)
        XCTAssertEqual(ump().wordsPerEvent, 2)
    }
}
```

(If two duplicate-word asserts in `testUMPBendRangeSetupWordsRPN0` look redundant once written, keep only `testUMPBendRangeSetupDataEntry` + a count assert; both exist here to force correct select→data→null ordering.)

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' test 2>&1 | grep -E "error|TEST" | head -10
```

Expected: FAIL — `UMPEncoder`/`MIDIMode` not defined (compile error).

- [ ] **Step 3: Implement `sleight/MIDI/UMPEncoder.swift`**

```swift
import Foundation
import CoreMIDI

/// Output protocol selector (persisted as string in AppSettings).
public enum MIDIMode: String, Codable, CaseIterable {
    case ump, mpe, legacy
}

/// Continuous-glide toggle (persisted as string in AppSettings).
public enum GlideMode: String, Codable, CaseIterable {
    case stepped, glide
}

/// Pure encoder: MIDIEvent → UMP words for the selected mode. No CoreMIDI
/// client state, so every word is unit-testable.
///
/// Group 0 everywhere. Human channel 1 = channel nibble 0 (v1 `0x90` shape);
/// MPE routes notes + per-note bend to nibble 1 ("channel 2") and keeps CC
/// global on nibble 0, per the MPE spec's zone layout.
public struct UMPEncoder {
    public let mode: MIDIMode
    /// User-facing bend range (stepped UMP + legacy); MPE is fixed 48; glide
    /// UMP uses the octave span so the whole band fits inside one note's bend.
    public var userBendRange: Double
    public var glide: Bool
    /// Total pitch band extent in semitones (octaves × 12). Glide range = ceil.
    public var octaveSpanSemitones: Double = 24

    public init(mode: MIDIMode, userBendRange: Double, glide: Bool) {
        self.mode = mode
        self.userBendRange = userBendRange
        self.glide = glide
    }

    public var protocolID: MIDIProtocolID {
        mode == .ump ? kMIDIProtocol_2_0 : kMIDIProtocol_1_0
    }

    public var wordsPerEvent: Int { mode == .ump ? 2 : 1 }

    public var bendRangeSemitones: Double {
        switch mode {
        case .ump: return glide ? min(96, (octaveSpanSemitones / 12).rounded(.up) * 12) : userBendRange
        case .mpe: return 48
        case .legacy: return userBendRange
        }
    }

    public func encode(_ event: MIDIEvent) -> [UInt32] {
        switch mode {
        case .ump: return encodeUMP(event)
        case .mpe: return encodeMPE(event)
        case .legacy: return encodeMIDI1(event, noteChannel: 0)
        }
    }

    // MARK: MIDI 2.0 (UMP, 64-bit messages)

    private func encodeUMP(_ e: MIDIEvent) -> [UInt32] {
        let ch = umpNoteChannel
        switch e.kind {
        case let .noteOn(note, velocity):
            let v = UInt16((min(max(velocity, 0), 1) * 65535).rounded())
            return [midi2(kMIDICVStatusNoteOn, ch, UInt32(note) << 8, UInt32(v) << 16)]
        case let .noteOff(note):
            return [midi2(kMIDICVStatusNoteOff, ch, UInt32(note) << 8, 0)]
        case let .perNotePitchBendSemitones(note, semis):
            return [midi2(kMIDICVStatusPerNotePitchBend, ch, UInt32(note) << 8,
                          umpBendValue(semis: semis))]
        case let .cc(controller, value):
            return [midi2(kMIDICVStatusControlChange, 0, UInt32(controller) << 8, UInt32(value) << 25)]
        }
    }

    private var umpNoteChannel: UInt32 { 0 }   // monophonic: channel 1

    /// 32-bit per-note bend: 0x80000000 = no bend, ±bendRange spans full span.
    private func umpBendValue(semis: Double) -> UInt32 {
        let clamped = min(max(semis / max(bendRangeSemitones, 1e-9), -1), 1)
        if clamped == 0 { return 0x8000_0000 }
        return UInt32(0x8000_0000) &+ UInt32(bitPattern: Int32((clamped * 0x7FFF_FFFF).rounded()))
    }

    // MARK: MIDI 1.0 (legacy + MPE, 32-bit MIDI1UP words)

    private func encodeMPE(_ e: MIDIEvent) -> [UInt32] {
        switch e.kind {
        case let .noteOn(note, velocity):
            return [midi1(kMIDICVStatusNoteOn, 1, UInt32(note) << 8 | midi1Velocity(velocity))]
        case let .noteOff(note):
            return [midi1(kMIDICVStatusNoteOff, 1, UInt32(note) << 8)]
        case let .perNotePitchBendSemitones(_, semis):
            let v = midi1BendValue(semis: semis)   // range 48 via bendRangeSemitones
            return [midi1(kMIDICVStatusPitchBend, 1, UInt32(v & 0x7F) | UInt32((v >> 7) & 0x7F) << 8)]
        case let .cc(controller, value):
            return [midi1(kMIDICVStatusControlChange, 0, UInt32(controller) << 8 | UInt32(value))]
        }
    }

    private func encodeMIDI1(_ e: MIDIEvent, noteChannel: UInt32) -> [UInt32] {
        switch e.kind {
        case let .noteOn(note, velocity):
            return [midi1(kMIDICVStatusNoteOn, noteChannel, UInt32(note) << 8 | midi1Velocity(velocity))]
        case let .noteOff(note):
            return [midi1(kMIDICVStatusNoteOff, noteChannel, UInt32(note) << 8)]
        case let .perNotePitchBendSemitones(_, semis):
            let v = midi1BendValue(semis: semis)
            return [midi1(kMIDICVStatusPitchBend, noteChannel, UInt32(v & 0x7F) | UInt32((v >> 7) & 0x7F) << 8)]
        case let .cc(controller, value):
            return [midi1(kMIDICVStatusControlChange, noteChannel, UInt32(controller) << 8 | UInt32(value))]
        }
    }

    private func midi1Velocity(_ velocity: Double) -> UInt32 {
        UInt32((min(max(velocity, 0), 1) * 127).rounded())
    }

    private func midi1BendValue(semis: Double) -> Int {
        let clamped = min(max(semis / max(bendRangeSemitones, 1e-9), -1), 1)
        return 8192 + Int((clamped * 8191).rounded())
    }

    // Word builders (mirror the SDK's CF_INLINE helpers bit-for-bit)

    private func midi2(_ status: UInt32, _ channel: UInt32, _ index: UInt32, _ value: UInt32) -> UInt32 {
        0x4000_0000 | status << 20 | channel << 16 | index
    }

    private func midi1(_ status: UInt32, _ channel: UInt32, _ data: UInt32) -> UInt32 {
        0x2000_0000 | status << 20 | channel << 16 | data
    }

    // MARK: Bend-range / MPE setup

    /// Words sent when the source comes up or expression settings change.
    /// - UMP: RPN 0 select → data entry (±range, CC6 msb) → RPN null.
    /// - MPE: MPE config RPN 6 = 1 member channel (this is what tells the
    ///   receiver "MIDI ch 2 is MPE"), then bend range RPN 0 = 48, nulled.
    /// - Legacy: nothing (receiver default ±2 is v1 behavior).
    public func bendRangeSetupWords() -> [UInt32] {
        switch mode {
        case .legacy:
            return []
        case .mpe:
            func rpn(_ msb: UInt32, _ lsb: UInt32, _ d1: UInt32, _ d2: UInt32) -> [UInt32] {
                [midi1(kMIDICVStatusControlChange, 0, 101 << 8 | msb),
                 midi1(kMIDICVStatusControlChange, 0, 100 << 8 | lsb),
                 midi1(kMIDICVStatusControlChange, 0, 6 << 8 | d1),
                 midi1(kMIDICVStatusControlChange, 0, 38 << 8 | d2),
                 midi1(kMIDICVStatusControlChange, 0, 101 << 8 | 127),
                 midi1(kMIDICVStatusControlChange, 0, 100 << 8 | 127)]
            }
            return rpn(0, 1, 0, 1)          // MPE config: 1 member channel (ch 2)
                 + rpn(48, 0, 48, 0)        // bend range 48 on the MPE zone
        case .ump:
            let r = UInt32(bendRangeSemitones.rounded(.up))
            return [midi2(kMIDICVStatusControlChange, 0, 101 << 8, 0),
                    midi2(kMIDICVStatusControlChange, 0, 100 << 8, 0),
                    midi2(kMIDICVStatusControlChange, 0, 6 << 8, r << 25),
                    midi2(kMIDICVStatusControlChange, 0, 38 << 8, 0),
                    midi2(kMIDICVStatusControlChange, 0, 101 << 8, 127 << 25),
                    midi2(kMIDICVStatusControlChange, 0, 100 << 8, 127 << 25)]
        }
    }
}
```

- [ ] **Step 4: Run encoder tests until green**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' -only-testing:sleightTests/UMPEncoderTests test 2>&1 | tail -5
```

Expected: PASS (all 17 encoder tests).

- [ ] **Step 5: Commit**

```bash
git add sleight/MIDI/UMPEncoder.swift sleightTests/UMPEncoderTests.swift
git commit -m "feat: UMPEncoder — UMP/MPE/legacy word encoding with RPN bend-range setup"
```

---

### Task 3: `MIDISource` — event-list send path + protocol recreate

**Files:**
- Modify: `sleight/MIDI/MIDISource.swift`

**Interfaces:**
- Consumes: `UMPEncoder` (Task 2).
- Produces (used by Task 5):
  - `MIDISource.shared` unchanged.
  - `func configure(mode: MIDIMode, userBendRange: Double, octaveSpanSemitones: Double, glide: Bool) -> Bool` — recreates the endpoint when mode changes (returns false on failure, keeping last-good mode); sends bend-range setup words whenever computed ranges change.
  - `func send(_ events: [MIDIEvent])` — unchanged call site in `Pipeline.process`.

- [ ] **Step 1: Rewrite `sleight/MIDI/MIDISource.swift`** (delete `MIDIPacketList` path entirely)

Keep the `MIDIEvent.encode` extension from Task 1 (legacy fixture reference), add protocol-mode plumbing:

```swift
import Foundation
import CoreMIDI

/// CoreMIDI virtual source. Appears in Logic's MIDI input list as "Sleight".
/// One send path for every protocol: MIDIEventList of UMP words. The source is
/// (re)created under a protocol via MIDISourceCreateWithProtocol; recreating
/// bumps host re-enumeration, which is why mode changes are rare/explicit.
public final class MIDISource {
    public static let shared = MIDISource()

    private var client: MIDIClientRef = 0
    private var source: MIDIEndpointRef = 0
    /// 64 KB — the documented maximum event-list size.
    private var scratch = [UInt32](repeating: 0, count: 16384)
    private var encoder = UMPEncoder(mode: .ump, userBendRange: 2, glide: true)

    public private(set) var name: String
    public private(set) var mode: MIDIMode = .ump

    public init(name: String = "Sleight") {
        self.name = name
        let status = MIDIClientCreate(name as CFString, nil, nil, &client)
        guard status == noErr else { return }
        recreateSource(protocol: encoder.protocolID)
    }

    /// Push settings from the controller. Recreates the endpoint when the
    /// protocol mode changes (many hosts enumerate sources once), and re-sends
    /// bend-range RPNs whenever the computed range changes. Returns false when
    /// a mode recreate failed (mode stays at the last-good value).
    @discardableResult
    public func configure(mode: MIDIMode, userBendRange: Double,
                          octaveSpanSemitones: Double, glide: Bool) -> Bool {
        let oldConfigured = encoder
        let oldMode = mode
        encoder = UMPEncoder(mode: mode, userBendRange: userBendRange, glide: glide)
        encoder.octaveSpanSemitones = octaveSpanSemitones
        if mode != oldMode {
            guard recreateSource(protocol: encoder.protocolID) else {
                encoder = oldConfigured      // keep last-good mode + encoding
                mode = oldMode
                return false
            }
            self.mode = mode
        }
        transmit(encoder.bendRangeSetupWords())
        return true
    }

    /// Send a batch of events, timestamped now.
    public func send(_ events: [MIDIEvent]) {
        guard source != 0, !events.isEmpty else { return }
        let chunks = events.map { encoder.encode($0) }
        transmit(chunks)
    }

    private func recreateSource(protocol: MIDIProtocolID) -> Bool {
        if source != 0 { MIDIEndpointDispose(source); source = 0 }
        var ref: MIDIEndpointRef = 0
        guard MIDISourceCreateWithProtocol(client, name as CFString, protocol, &ref) == noErr else {
            return false
        }
        source = ref
        return true
    }

    /// Build one event list and transmit. Timestamps: mach_absolute_time "now"
    /// (MIDIReceivedEventList requires the sender to stamp; 0 is NOT "now").
    private func transmit(_ chunks: [[UInt32]]) {
        guard source != 0, !chunks.isEmpty else { return }
        let now: UInt64 = mach_absolute_time()
        let listSize = MemoryLayout<UInt32>.size * scratch.count
        let ok = withUnsafeMutableBytes(of: &scratch) { raw -> Bool in
            let list = raw.baseAddress!.assumingMemoryBound(to: MIDIEventList.self)
            var packet = MIDIEventListInit(list, encoder.protocolID)
            for chunk in chunks {
                var next: UnsafeMutablePointer<MIDIEventPacket>?
                chunk.withUnsafeBufferPointer { buf in
                    guard let base = buf.baseAddress else { return }
                    next = MIDIEventListAdd(list, listSize, packet, now, UInt32(buf.count), base)
                }
                guard let unwrapped = next else { return false }
                packet = unwrapped
            }
            return MIDIReceivedEventList(source, list) == noErr
        }
        if !ok { /* transient CoreMIDI failure; drop the batch silently */ }
    }
}
```

Then in `sleight/Pipeline/Pipeline.swift` change the send call (bend range now lives in the encoder):

```swift
        if !practiceMode {
            midiSource?.send(events)
        }
```

- [ ] **Step 2: Build + full test run** (MIDI virtual endpoints are exercised at runtime; unit tests validate words, this validates compilation + lifecycle)

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: PASS.

- [ ] **Step 3: Smoke-run the app once (Logic or MIDI Monitor listening on "Sleight", legacy behavior must be indistinguishable from v1)** — build & launch:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' build 2>&1 | tail -3 && open build/Build/Products/Debug/sleight.app
```

Expected: notes still sound / bytes identical to v1 (default UMP encoder in legacy-equivalent mode words = same bytes on the wire for MIDI 1.0 destinations).

- [ ] **Step 4: Commit**

```bash
git add sleight/MIDI/MIDISource.swift sleight/Pipeline/Pipeline.swift
git commit -m "feat: unified MIDIEventList send path, protocol-configurable virtual source"
```

---

### Task 4: Glide in Theremin

**Files:**
- Modify: `sleight/Instruments/Theremin.swift`
- Modify: `sleightTests/ThereminTests.swift`

**Interfaces:**
- Consumes: `GlideMode` (Task 2), `perNotePitchBendSemitones` (Task 1).
- Produces: `Theremin.glideMode: GlideMode` (default `.glide`), `currentRawPitch: Double` (`private(set)`), unchanged `update(hands:dt:)` signature. `SleightController.applySettings` sets it (Task 5); tests set it directly.

- [ ] **Step 1: Write failing glide tests (append to `sleightTests/ThereminTests.swift`)**

```swift
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
t        }
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
        let reset = evs.compactMap { if case .perNotePitchBendSemitones(let n, let s) = $0.kind where n == held { return s }; return nil }.last
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

    func testGlideBendClampedAtBandEdges() {
        let t = Theremin()
        t.glideMode = .glide
        t.octaves = 2
        _ = t.update(hands: [rightHand(x: 0.55, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)], dt: 1/60)
        let evs = t.update(hands: [rightHand(x: 0.95, y: 0.5, pinchNorm: 0.2), leftHand(y: 0.4)], dt: 1/60)
        let bend = evs.compactMap { if case .perNotePitchBendSemitones(_, let s) = $0.kind { return s }; return nil }.first
        XCTAssertNotNil(bend)
        XCTAssertLessThanOrEqual(abs(bend!), 26.0)   // inside encoder range + margin
    }
```

- [ ] **Step 2: Run to verify the glide tests fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' -only-testing:sleightTests/ThereminTests test 2>&1 | grep -E "error|failures" | head -10
```

Expected: FAIL — `glideMode` not defined on Theremin.

- [ ] **Step 3: Implement glide in `sleight/Instruments/Theremin.swift`**

Add state + mode:

```swift
    public var glideMode: GlideMode = .glide
    public private(set) var currentRawPitch: Double = 60   // pre-quantization hand pitch
```

Store raw pitch in the pitch block (already computed as `raw`):

```swift
        if let r = right {
            let x = r.points[Landmark.indexTip].x
            let xNorm = min(max((x - pitchBand.lowerBound) / (pitchBand.upperBound - pitchBand.lowerBound), 0), 1)
            let raw = Double(root) + xNorm * 12 * octaves
            currentRawPitch = raw
            let pitch = MusicTheory.quantize(raw, scale: scale, root: root % 12)
            currentPitch = pitch
            let v = vibrato.process(raw, dt: dt)
            vibratoDepthCents = v.depthCents * vibratoDepthScale
            vibratoActive = v.active
        }
```

Gate section becomes (replaces Task 1's `if wantGate` block):

```swift
        let baseNote = UInt8(currentPitch.rounded())
        let wantGate = pinchActive && !belowFloor

        if wantGate {
            if !isGateOpen {
                isGateOpen = true
                currentNote = baseNote
                let vel = Self.velocity(pinchAmount: lastPinchAmount, onThreshold: pinch.onThreshold)
                events.append(MIDIEvent(kind: .noteOn(note: baseNote, velocity: vel), timestamp: t))
            } else if glideMode == .stepped, baseNote != currentNote {
                // stepped: crossing a tone = legible re-articulation (v1 behavior)
                if let old = currentNote {
                    events.append(MIDIEvent(kind: .noteOff(note: old), timestamp: t))
                }
                currentNote = baseNote
                let vel = Self.velocity(pinchAmount: lastPinchAmount, onThreshold: pinch.onThreshold)
                events.append(MIDIEvent(kind: .noteOn(note: baseNote, velocity: vel), timestamp: t))
            }
            // Continuous expression while held. Glide bends from the RAW hand
            // pitch to the held note (no re-triggers ever); stepped keeps v1's
            // quantized-frac + vibrato shape.
            if let n = currentNote {
                let bend: Double
                if glideMode == .glide {
                    bend = (currentRawPitch - Double(n)) + vibratoDepthCents / 100
                } else {
                    bend = bendSemitones()
                }
                events.append(MIDIEvent(kind: .perNotePitchBendSemitones(note: n, bend), timestamp: t))
            }
            events.append(MIDIEvent(kind: .cc(7, volume), timestamp: t))
        } else if isGateOpen {
            // pinch released, volume floored, or hand lost → safe close: note-off
            // + bend center reset (so a later articulation on the same note can't
            // inherit a stale wild bend). Glide holds volume (no cc7=0).
            isGateOpen = false
            if let n = currentNote {
                events.append(MIDIEvent(kind: .noteOff(note: n), timestamp: t))
                if glideMode == .glide {
                    events.append(MIDIEvent(kind: .perNotePitchBendSemitones(note: n, 0), timestamp: t))
                }
            }
            currentNote = nil
            if glideMode == .stepped {
                events.append(MIDIEvent(kind: .cc(7, 0), timestamp: t))
                lastVolume = 0
            }
        }
```

- [ ] **Step 4: Run Theremin + pipeline + MIDI tests (whole suite)**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: PASS (v1 gate/gate-loss tests unchanged; note the `.perNotePitchBendSemitones` pattern in `testPinchStartsNoteAndEmitsBendAndCC7` still matches).

- [ ] **Step 5: Commit**

```bash
git add sleight/Instruments/Theremin.swift sleightTests/ThereminTests.swift
git commit -m "feat: continuous glide while held (per-note bend from raw hand pitch)"
```

---

### Task 4.5: Settings + UI + README

**Files:**
- Modify: `sleight/Support/Settings.swift`
- Modify: `sleight/App/SleightController.swift`
- Modify: `sleight/App/ContentView.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `MIDIMode`/`GlideMode`, `MIDISource.configure` (Tasks 2–3), `Theremin.glideMode` (Task 4).
- Produces: `AppSettings.midiMode: MIDIMode`, `AppSettings.glide: GlideMode`; Settings sheet "MIDI protocol" picker + glide toggle.

- [ ] **Step 1: Extend AppSettings** — add published fields (same pattern as existing):

```swift
    @Published var midiModeRaw: String
    @Published var glideRaw: String

    var midiMode: MIDIMode { MIDIMode(rawValue: midiModeRaw) ?? .ump }
    var glide: GlideMode { GlideMode(rawValue: glideRaw) ?? .glide }
```

init:

```swift
        midiModeRaw = d.string(forKey: "midiMode") ?? MIDIMode.ump.rawValue
        glideRaw = d.string(forKey: "glide") ?? GlideMode.glide.rawValue
```

persist:

```swift
        $midiModeRaw.sink { d.set($0, forKey: "midiMode") }.store(in: &cancellables)
        $glideRaw.sink { d.set($0, forKey: "glide") }.store(in: &cancellables)
```

- [ ] **Step 2: Wire SleightController.applySettings** — append:

```swift
        inst.glideMode = settings.midiMode == .legacy ? .stepped : settings.glide
        let octaveSpan = inst.octaves * 12
        let ok = pipeline.midiSource?.configure(mode: settings.midiMode,
                                                userBendRange: settings.bendRange,
                                                octaveSpanSemitones: octaveSpan,
                                                glide: inst.glideMode == .glide) ?? true
        midiConfigFailed = !ok
```

Add `@Published private(set) var midiConfigFailed = false` on the controller; the TrackingCard diagnostic appends `| midi: \(settings.midiMode.rawValue)\(midiConfigFailed ? " (RECREATE FAILED)" : "")`.

- [ ] **Step 3: Settings UI in `SettingsSheet`** — inside the "Music" GroupBox HStack, add:

```swift
                    Picker("MIDI protocol", selection: Binding(
                        get: { controller.settings.midiModeRaw },
                        set: { controller.settings.midiModeRaw = $0; controller.applySettings() })) {
                        Text("MIDI 2.0 (UMP)").tag(MIDIMode.ump.rawValue)
                        Text("MPE (MIDI 1.1)").tag(MIDIMode.mpe.rawValue)
                        Text("MIDI 1.1").tag(MIDIMode.legacy.rawValue)
                    }
                    Toggle("Glide", isOn: Binding(
                        get: { controller.settings.glide == .glide && controller.settings.midiMode != .legacy },
                        set: { controller.settings.glideRaw = $0 ? GlideMode.glide.rawValue : GlideMode.stepped.rawValue
                               controller.applySettings() }))
                        .disabled(controller.settings.midiMode == .legacy)
```

(Bend-range picker already exists — it now feeds stepped/legacy modes; leave as is.)

- [ ] **Step 4: README** — update the Instruments table row Theremin to mention glide, replace the Roadmap bullet list with:

```markdown
- v2 ✅: MIDI 2.0 / MPE / MIDI 1.1 output (per-note pitch bend, 32-bit), glide mode
- v2.1: per-finger polyphony (2–4 simultaneous MPE notes)
- v3: ESP32 wireless-glove mode (IMU-fused tracking for away-from-desk play), AUv3 plugin, ribbon instrument
```

and add a "## MIDI protocol" section:

```markdown
## MIDI protocol

Sleight emits three protocols from a virtual source named **Sleight** (Settings → MIDI protocol):

| Mode | What you get | Use when |
|---|---|---|
| **MIDI 2.0 (UMP)** (default) | 16-bit velocity, 32-bit per-note pitch bend, explicit bend-range RPN | DAW + instruments with MIDI 2.0 support |
| **MPE (MIDI 1.1)** | Standard MPE: global CC on ch 1, notes + per-note bend (±48) on ch 2 | Any MPE-capable instrument (most modern DAWs) |
| **MIDI 1.1** | Classic bytes — pitch bend ±2 (user-selectable range) | Older hosts that only list MIDI 1.0 sources |

**Glide**: while a note is held (pinched), pitch follows your hand continuously instead of stepping to the next scale tone — the scale quantizes where notes *start* (articulation), the smear between tones is the theremin sound. UMP and MPE only; the toggle is disabled in MIDI 1.1 mode.

If your DAW doesn't list **Sleight** after a protocol change, it caches source enumeration: restart the DAW's MIDI device list (or switch the mode once more).
```

- [ ] **Step 5: Full build + test**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add sleight/Support/Settings.swift sleight/App/SleightController.swift sleight/App/ContentView.swift README.md
git commit -m "feat: MIDI protocol + glide settings, README v2 docs"
```

---

### Task 5: Release gate — live verification (manual, with James)

**Files:**
- Modify: none (checklist runs against the built app)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Run the full suite one more time, clean build**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: PASS (this is the CI-equivalent gate).

- [ ] **Step 2: Live checklist with James (gates the v2 release):**
  1. Logic 11 + **UMP mode**: "Sleight" appears as a MIDI 2.0-capable input; record a glided phrase → continuous pitch curve, no repeated note triggers; 16-bit velocity spread visible.
  2. Logic 11 + **MPE mode**: glide records as MPE per-note bend on ch 2; CC7 stays global.
  3. **MIDI 1.1 mode**: MIDI Monitor byte-diff vs v1 capture (should be identical).
  4. Optional second DAW (Ableton) MPE sanity check.

- [ ] **Step 3: Tag release** (tag-triggered CI, same pattern as ltx-video-mac): merge to main, `git tag v2.0.0`, `git push origin v2.0.0`, then `gh run watch --exit-status` and `gh release view v2.0.0` to verify.

---

## Plan Self-Review Notes

- Spec §4.1 → Tasks 1; §4.2 → Tasks 2–3; §4.3 → Tasks 1/3 (TestSynth consumes raw events); §4.4 → Task 4; §4.5 → Task 4.5; §6 → Tasks 2–5; §7 mitigations covered in Tasks 3/4/4.5.
- Type consistency: `MIDIMode`/`GlideMode` rawValues match across Settings strings and encoder; `configure(mode:userBendRange:octaveSpanSemitones:glide:)` matches `applySettings()` call; `bendRangeSetupWords()` covers UMP RPN 0 + MPE init per spec §4.2.
- Literal word vectors in tests are hand-derived from the SDK's CF_INLINE formulas (group 0, note ch1 = nibble 0, MPE ch2 = nibble 1); if a literal ever disagrees with the SDK helper, the SDK header wins — fix the encoder, not the test.