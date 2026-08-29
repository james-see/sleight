import Foundation

/// Maps voice slots to MPE channel nibbles for multi-note expression.
///
/// - UMP mode: always channel 0 (per-note management is by note number in the
///   64-bit message; no channel routing needed).
/// - MPE mode: voice 0 → nibble 1 (MIDI ch 2), voice 1 → nibble 2, etc.
///   Channel 0 (nibble 0) is reserved for global CC.
/// - Legacy mode: always channel 0 (monophonic, last-note priority).
public enum ChannelMode {
    case ump
    case mpe(maxVoices: Int)
    case legacy
}

public struct ChannelAllocator {
    private let mode: ChannelMode
    private var voiceChannels: [Int: UInt8] = [:]  // voice → channel nibble

    public init(mode: ChannelMode) {
        self.mode = mode
    }

    /// Allocate a channel for a voice that is starting. If the voice already
    /// has a channel, returns the existing one (no double-allocation).
    @discardableResult
    public mutating func noteOn(voice: Int) -> UInt8 {
        switch mode {
        case .ump, .legacy:
            return 0
        case .mpe(let maxVoices):
            if let existing = voiceChannels[voice] { return existing }
            let used = Set(voiceChannels.values)
            for ch in 1...UInt8(maxVoices) {
                if !used.contains(ch) {
                    voiceChannels[voice] = ch
                    return ch
                }
            }
            voiceChannels[voice] = 1
            return 1
        }
    }

    public mutating func noteOff(voice: Int) {
        voiceChannels.removeValue(forKey: voice)
    }

    /// Current channel nibble for a voice (0 if not sounding).
    public func channel(for voice: Int) -> UInt8 {
        switch mode {
        case .ump, .legacy: return 0
        case .mpe: return voiceChannels[voice] ?? 0
        }
    }

    /// Release all voices. Call on mode change or instrument switch.
    public mutating func reset() {
        voiceChannels.removeAll()
    }
}
