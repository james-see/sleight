import Foundation

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

public protocol Instrument: AnyObject {
    var id: String { get }
    var displayName: String { get }
    /// Consume one pipeline tick; return the MIDI events for this tick.
    func update(hands: [HandFrame], dt: Double) -> [MIDIEvent]
}

public struct InstrumentRegistry {
    public static let v1: [any Instrument.Type] = [Theremin.self]
}