import Foundation

public struct MIDIEvent: Equatable {
    public enum Kind: Equatable {
        case noteOn(note: UInt8, velocity: Double, channel: UInt8 = 0)          // velocity = final velocity 0…1
        case noteOff(note: UInt8, channel: UInt8 = 0)
        case perNotePitchBendSemitones(note: UInt8, Double, channel: UInt8 = 0) // bend attached to a sounding note
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
    var pitchBand: ClosedRange<Double> { get set }
    var volumeBand: ClosedRange<Double> { get set }
    var scale: Scale { get set }
    var root: Int { get set }
    var octaves: Double { get set }
    /// Consume one pipeline tick; return the MIDI events for this tick.
    func update(hands: [HandFrame], dt: Double) -> [MIDIEvent]
}

/// Overlay state defaults — instruments that expose live state override these.
public extension Instrument {
    var isGateOpen: Bool { false }
    var currentPitch: Double { 60 }
    var vibratoActive: Bool { false }
    var lastPinchAmount: Double { 1.0 }
    var lastVolume: UInt8 { 0 }
    var bendRangeSemitones: Double { get { 2 } set {} }
    var glideMode: GlideMode { get { .glide } set {} }
}

public enum InstrumentType: String, CaseIterable, Identifiable {
    case theremin = "theremin"
    case polyPads = "poly-pads"
    public var id: String { rawValue }
}

public struct InstrumentRegistry {
    public static let v1: [any Instrument.Type] = [Theremin.self, PolyPads.self]
    public static func make(_ type: InstrumentType) -> any Instrument {
        switch type {
        case .theremin: return Theremin()
        case .polyPads: return PolyPads()
        }
    }
}