import Foundation

/// v1 instrument: right hand controls pitch (horizontal), left hand controls
/// volume (vertical), pinch gates notes, hand oscillation becomes vibrato.
public final class Theremin: Instrument {
    public var id: String { "theremin" }
    public var displayName: String { "Theremin" }

    // Calibration
    public var pitchBand: ClosedRange<Double> = 0.55...0.95
    public var volumeBand: ClosedRange<Double> = 0.1...0.7
    public var scale: Scale = .minorPentatonic
    public var root: Int = 60                  // C4
    public var octaves: Double = 2
    public var bendRangeSemitones: Double = 2
    public var vibratoDepthScale: Double = 1.0
    public var defaultVolume: UInt8 = 100      // used when the left hand is absent

    // State
    public private(set) var currentPitch: Double = 60
    public private(set) var isGateOpen = false
    public private(set) var currentNote: UInt8?
    public private(set) var lastVolume: UInt8 = 0
    private var pinch = PinchDetector()
    private var vibrato = VibratoEngine()
    private var vibratoDepthCents: Double = 0
    private var clock: Double = 0

    public init() {}

    public func update(hands: [HandFrame], dt: Double) -> [MIDIEvent] {
        clock += dt
        var events: [MIDIEvent] = []
        let t = clock

        let right = hands.first { $0.side == .right }
        let left = hands.first { $0.side == .left }

        // ---- pitch (right index-tip x → continuous, quantized) ----
        if let r = right {
            let x = r.points[Landmark.indexTip].x
            let xNorm = min(max((x - pitchBand.lowerBound) / (pitchBand.upperBound - pitchBand.lowerBound), 0), 1)
            let pitch = MusicTheory.quantize(Double(root) + xNorm * 12 * octaves, scale: scale, root: root % 12)
            currentPitch = pitch
            let v = vibrato.process(pitch, dt: dt)
            vibratoDepthCents = v.depthCents * vibratoDepthScale
        }

        // ---- volume (left wrist y, inverted: up = loud) ----
        var volume: UInt8
        var belowFloor = false
        if let l = left {
            let y = l.points[Landmark.wrist].y
            if y <= volumeBand.lowerBound {
                volume = 127
            } else if y >= volumeBand.upperBound {
                volume = 0
                belowFloor = true            // deliberate mute: hand dropped below the band
            } else {
                let n = 1 - (y - volumeBand.lowerBound) / (volumeBand.upperBound - volumeBand.lowerBound)
                volume = UInt8((n * 127).rounded())
            }
            lastVolume = volume
        } else {
            // Volume hand absent: hold last level so one-handed play keeps working.
            volume = lastVolume == 0 ? defaultVolume : lastVolume
        }

        // ---- gate (right-hand pinch with hysteresis) ----
        var pinchActive = false
        if let r = right {
            pinchActive = pinch.update(r).isActive
        }

        let baseNote = UInt8(currentPitch.rounded())
        let wantGate = pinchActive && !belowFloor

        if wantGate {
            if !isGateOpen {
                isGateOpen = true
                currentNote = baseNote
                events.append(MIDIEvent(kind: .noteOn(baseNote, velocity: 100), timestamp: t))
            } else if baseNote != currentNote {
                // base note crossed to a new integer → legible re-articulation
                if let old = currentNote {
                    events.append(MIDIEvent(kind: .noteOff(old), timestamp: t))
                }
                currentNote = baseNote
                events.append(MIDIEvent(kind: .noteOn(baseNote, velocity: 100), timestamp: t))
            }
            // continuous expression while held
            events.append(MIDIEvent(kind: .pitchBendSemitones(bendSemitones()), timestamp: t))
            events.append(MIDIEvent(kind: .cc(7, volume), timestamp: t))
        } else if isGateOpen {
            // pinch released, volume floored, or right hand lost → safe note-off
            isGateOpen = false
            if let n = currentNote {
                events.append(MIDIEvent(kind: .noteOff(n), timestamp: t))
            }
            currentNote = nil
            events.append(MIDIEvent(kind: .cc(7, 0), timestamp: t))
            lastVolume = 0
        }

        return events
    }

    private func bendSemitones() -> Double {
        let base = currentPitch.rounded()
        let frac = currentPitch - base            // ±0.5 around the held base note
        let bend = frac + vibratoDepthCents / 100
        return min(max(bend, -bendRangeSemitones), bendRangeSemitones)
    }
}