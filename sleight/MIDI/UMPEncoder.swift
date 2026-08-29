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
    /// User-facing bend range (stepped UMP + legacy). MPE is fixed 48; glide
    /// UMP uses the octave span so the whole band fits inside one note's bend.
    public var userBendRange: Double
    public var glide: Bool
    /// Total pitch band extent in semitones (octaves × 12). Glide range = ceil
    /// to whole semitones, capped so huge octave settings can't overflow RPN.
    public var octaveSpanSemitones: Double = 24

    public init(mode: MIDIMode, userBendRange: Double, glide: Bool) {
        self.mode = mode
        self.userBendRange = userBendRange
        self.glide = glide
    }

    public var protocolID: MIDIProtocolID {
        // MIDIProtocolID's C cases don't import as Swift members in this
        // toolchain; rawValue init is the supported path (1 = MIDI 1.0, 2 = 2.0).
        MIDIProtocolID(rawValue: mode == .ump ? 2 : 1)!
    }

    public var wordsPerEvent: Int { mode == .ump ? 2 : 1 }

    public var bendRangeSemitones: Double {
        switch mode {
        case .ump:
            guard glide else { return userBendRange }
            return min(96, (octaveSpanSemitones / 12).rounded(.up) * 12)
        case .mpe: return 48
        case .legacy: return userBendRange
        }
    }

    public func encode(_ event: MIDIEvent) -> [UInt32] {
        switch mode {
        case .ump: return encodeUMP(event)
        case .mpe: return encodeMPE(event)
        case .legacy: return encodeMIDI1(event, channel: 0)
        }
    }

    // MARK: MIDI 2.0 (UMP, 64-bit messages = word0 header + word1 value)

    private func encodeUMP(_ e: MIDIEvent) -> [UInt32] {
        switch e.kind {
        case let .noteOn(note, velocity, _):
            let v = UInt16((min(max(velocity, 0), 1) * 65535).rounded())
            return [midi2w0(MIDICVStatus.noteOn.rawValue, 0, UInt32(note) << 8), UInt32(v) << 16]
        case let .noteOff(note, _):
            return [midi2w0(MIDICVStatus.noteOff.rawValue, 0, UInt32(note) << 8), 0]
        case let .perNotePitchBendSemitones(note, semis, _):
            return [midi2w0(MIDICVStatus.perNotePitchBend.rawValue, 0, UInt32(note) << 8), umpBendValue(semis: semis)]
        case let .cc(controller, value):
            return [midi2w0(MIDICVStatus.controlChange.rawValue, 0, UInt32(controller) << 8), UInt32(value) << 25]
        }
    }

    /// 32-bit per-note bend: 0x80000000 = no bend, ±range spans the full span.
    private func umpBendValue(semis: Double) -> UInt32 {
        let clamped = min(max(semis / max(bendRangeSemitones, 1e-9), -1), 1)
        if clamped == 0 { return 0x8000_0000 }
        return UInt32(0x8000_0000) &+ UInt32(bitPattern: Int32((clamped * 0x7FFF_FFFF).rounded()))
    }

    // MARK: MIDI 1.0 (legacy + MPE, 32-bit MIDI1UP words)

    private func encodeMPE(_ e: MIDIEvent) -> [UInt32] {
        switch e.kind {
        case let .noteOn(note, velocity, channel):
            return [midi1(MIDICVStatus.noteOn.rawValue, UInt32(channel), UInt32(note) << 8 | midi1Velocity(velocity))]
        case let .noteOff(note, channel):
            return [midi1(MIDICVStatus.noteOff.rawValue, UInt32(channel), UInt32(note) << 8)]
        case let .perNotePitchBendSemitones(_, semis, channel):
            return [midi1(MIDICVStatus.pitchBend.rawValue, UInt32(channel), midi1BendData(semis: semis))]
        case let .cc(controller, value):
            return [midi1(MIDICVStatus.controlChange.rawValue, 0, UInt32(controller) << 8 | UInt32(value))]
        }
    }

    private func encodeMIDI1(_ e: MIDIEvent, channel: UInt32) -> [UInt32] {
        switch e.kind {
        case let .noteOn(note, velocity, ch):
            return [midi1(MIDICVStatus.noteOn.rawValue, UInt32(ch), UInt32(note) << 8 | midi1Velocity(velocity))]
        case let .noteOff(note, ch):
            return [midi1(MIDICVStatus.noteOff.rawValue, UInt32(ch), UInt32(note) << 8)]
        case let .perNotePitchBendSemitones(_, semis, ch):
            return [midi1(MIDICVStatus.pitchBend.rawValue, UInt32(ch), midi1BendData(semis: semis))]
        case let .cc(controller, value):
            return [midi1(MIDICVStatus.controlChange.rawValue, 0, UInt32(controller) << 8 | UInt32(value))]
        }
    }

    private func midi1Velocity(_ velocity: Double) -> UInt32 {
        UInt32((min(max(velocity, 0), 1) * 127).rounded())
    }

    /// 14-bit bend value with v1's exact asymmetric range (8192 down, 8191 up).
    private func midi1BendValue(semis: Double) -> Int {
        let clamped = min(max(semis / max(bendRangeSemitones, 1e-9), -1), 1)
        return 8192 + Int((clamped * 8191).rounded())
    }

    private func midi1BendData(semis: Double) -> UInt32 {
        let v = midi1BendValue(semis: semis)
        return UInt32(v & 0x7F) | UInt32((v >> 7) & 0x7F) << 8
    }

    // Word builders (mirror the SDK's CF_INLINE helpers bit-for-bit)

    /// 64-bit MIDI 2.0 message: word0 = (group|0x40)<<24 | (channel|status<<4)<<16 | index.
    private func midi2w0(_ status: UInt32, _ channel: UInt32, _ index: UInt32) -> UInt32 {
        0x4000_0000 | status << 20 | channel << 16 | index
    }

    private func midi1(_ status: UInt32, _ channel: UInt32, _ data: UInt32) -> UInt32 {
        0x2000_0000 | status << 20 | channel << 16 | data
    }

    // MARK: Bend-range / MPE setup

    /// Words sent when the source comes up or expression settings change.
    ///
    /// - UMP: RPN 0 (CC101 msb=0, CC100 lsb=0) → data entry (CC6 = ±range
    ///   semis, CC38 = 0) → RPN null. Sent on channel 1.
    /// - MPE: MPE configuration (RPN 0006 = 1 member channel, which is what
    ///   tells the receiver "channel 2 is the MPE note channel") then bend
    ///   range RPN 0000 = 48 — each frame closed with RPN null.
    /// - Legacy: nothing (receiver default ±2 is exactly v1 behavior).
    public func bendRangeSetupWords() -> [UInt32] {
        switch mode {
        case .legacy:
            return []
        case .mpe:
            let cc: (UInt32, UInt32) -> [UInt32] = { c, d in
                [midi1(MIDICVStatus.controlChange.rawValue, 0, c << 8 | d)]
            }
            return cc(101, 0) + cc(100, 6) + cc(6, 1) + cc(101, 127) + cc(100, 127)   // MPE config
                 + cc(101, 0) + cc(100, 0) + cc(6, 48) + cc(101, 127) + cc(100, 127)  // bend ±48
        case .ump:
            let r = UInt32(bendRangeSemitones.rounded(.up))
            // Each entry is a 2-word MIDI 2.0 CC: [header, value<<25].
            func cc(_ num: UInt32, _ val: UInt32) -> [UInt32] {
                [midi2w0(MIDICVStatus.controlChange.rawValue, 0, num << 8), val << 25]
            }
            return cc(101, 0) + cc(100, 0)        // RPN 0 select
                 + cc(6, r) + cc(38, 0)           // data entry (±range semis)
                 + cc(101, 127) + cc(100, 127)    // RPN null
        }
    }
}