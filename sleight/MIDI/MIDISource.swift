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
    /// 2 KB — plenty for one packet header (5 words) + a full 64-word UMP packet.
    private var scratch = [UInt32](repeating: 0, count: 512)
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

    /// Transmit. Timestamps: mach_absolute_time "now" (MIDIReceivedEventList
    /// requires the sender to stamp; 0 is NOT "now").
    ///
    /// The list is hand-packed into `scratch` using the public ABI layout
    /// (MIDIEventList { protocol, numPackets, packet{timeStamp, wordCount,
    /// words[]} }), then delivered with one MIDIReceivedEventList call per
    /// message — no MIDIEventListAdd at all.
    ///
    /// CRITICAL: this must be scratch.withUnsafeMutableBytes { } (the Array
    /// METHOD, pointing at the heap words), never the free function
    /// withUnsafeMutableBytes(of: &scratch), which points at the array STRUCT
    /// itself — writing the header there trashes the array's storage pointer
    /// (self-destruction: x0=0x100000002=(protocol,numPackets), swift_retain
    /// fault 0x100000008, the crash seen in app/test/probes on 2026-08-28).
    private func transmit(_ chunks: [[UInt32]]) {
        guard source != 0, !chunks.isEmpty else { return }
        let now: UInt64 = mach_absolute_time()
        let capacity = scratch.count   // hoisted: checked outside the pointer closure
        let protocolWord = UInt32(encoder.protocolID.rawValue)
        for chunk in chunks where !chunk.isEmpty {
            guard chunk.count <= 64, 5 + chunk.count <= capacity else { continue }
            let ok = scratch.withUnsafeMutableBytes { raw -> Bool in
                let base = raw.baseAddress!.assumingMemoryBound(to: UInt32.self)
                base[0] = protocolWord                       // list.protocol
                base[1] = 1                                  // list.numPackets = 1
                base[2] = UInt32(truncatingIfNeeded: now)    // packet.timeStamp lo
                base[3] = UInt32(truncatingIfNeeded: now >> 32) // packet.timeStamp hi
                base[4] = UInt32(chunk.count)                // packet.wordCount
                for (i, word) in chunk.enumerated() { base[5 + i] = word }
                let list = raw.baseAddress!.assumingMemoryBound(to: MIDIEventList.self)
                return MIDIReceivedEventList(source, list) == noErr
            }
            if !ok { break }  // transient CoreMIDI failure; drop the rest of the batch
        }
    }
}