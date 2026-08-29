import Foundation
import CoreMIDI

extension MIDIEvent {
    /// MIDI 1.1 channel-1 bytes (unchanged numbers; Double velocity rounds to 7-bit).
    /// Kept as the legacy fixture reference for tests; the live send path is UMP.
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

/// CoreMIDI virtual source. Appears in Logic's MIDI input list as "Sleight".
/// One send path for every protocol: a MIDIEventList of UMP words. The source
/// is (re)created under a protocol via MIDISourceCreateWithProtocol; recreating
/// bumps host re-enumeration, which is why mode changes are rare and explicit.
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
        createSource(protocol: encoder.protocolID)
    }

    /// Push settings from the controller. Recreates the endpoint when the
    /// protocol mode changes (many hosts enumerate sources once), and re-sends
    /// bend-range RPNs whenever the computed range changes. Returns false when
    /// a mode recreate failed (mode stays at the last-good value).
    @discardableResult
    public func configure(mode newMode: MIDIMode, userBendRange: Double,
                          octaveSpanSemitones: Double, glide: Bool) -> Bool {
        let lastGoodEncoder = encoder
        let lastGoodMode = mode
        encoder = UMPEncoder(mode: newMode, userBendRange: userBendRange, glide: glide)
        encoder.octaveSpanSemitones = octaveSpanSemitones
        if newMode != lastGoodMode {
            guard createSource(protocol: encoder.protocolID) else {
                encoder = lastGoodEncoder     // keep last-good mode + encoding
                mode = lastGoodMode
                return false
            }
            mode = newMode
        }
        transmit([encoder.bendRangeSetupWords()])
        return true
    }

    /// Send a batch of events, timestamped now.
    public func send(_ events: [MIDIEvent]) {
        guard source != 0, !events.isEmpty else { return }
        transmit(events.map { encoder.encode($0) })
    }

    @discardableResult
    private func createSource(protocol: MIDIProtocolID) -> Bool {
        if source != 0 { MIDIEndpointDispose(source); source = 0 }
        var ref: MIDIEndpointRef = 0
        guard MIDISourceCreateWithProtocol(client, name as CFString, `protocol`, &ref) == noErr else {
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
                chunk.withUnsafeBufferPointer { buf -> Void in
                    guard let base = buf.baseAddress else { return }
                    // Imports non-Optional in this SDK (no nullability annotation);
                    // 64 KB scratch vs 1-2-word events means "no room" can't occur.
                    packet = MIDIEventListAdd(list, listSize, packet, now, buf.count, base)
                }
            }
            return MIDIReceivedEventList(source, list) == noErr
        }
        if !ok { /* transient CoreMIDI failure; drop the batch silently */ }
    }
}