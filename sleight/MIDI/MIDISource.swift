import Foundation
import CoreMIDI

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

/// CoreMIDI virtual source. Appears in Logic's MIDI input list as "Sleight".
public final class MIDISource {
    public static let shared = MIDISource()

    private var client: MIDIClientRef = 0
    private var source: MIDIEndpointRef = 0
    private var scratch = [UInt8](repeating: 0, count: 65536)

    public private(set) var name: String

    public init(name: String = "Sleight") {
        self.name = name
        let status = MIDIClientCreate(name as CFString, nil, nil, &client)
        guard status == noErr else { return }
        MIDISourceCreate(client, name as CFString, &source)
    }

    /// Send a batch of events, timestamped now.
    public func send(_ events: [MIDIEvent], bendRange: Double) {
        guard source != 0, !events.isEmpty else { return }
        let now: UInt64 = mach_absolute_time()
        let packets: [Packet] = events.map { Packet(bytes: $0.encode(bendRangeSemitones: bendRange)) }
        let ok = withUnsafeMutableBytes(of: &scratch) { raw -> Bool in
            let list = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            var packet = MIDIPacketListInit(list)
            for p in packets {
                let next: UnsafeMutablePointer<MIDIPacket>? = p.bytes.withUnsafeBufferPointer { buf in
                    guard let base = buf.baseAddress else { return nil }
                    return MIDIPacketListAdd(list, MemoryLayout<MIDIPacketList>.size, packet, now, p.bytes.count, base)
                }
                guard let unwrapped = next else { return false }
                packet = unwrapped
            }
            return MIDIReceived(source, list) == noErr
        }
        if !ok { /* transient CoreMIDI failure; drop the batch silently */ }
    }

    private struct Packet { let bytes: [UInt8] }
}