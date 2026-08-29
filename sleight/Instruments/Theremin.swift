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

    /// Softest velocity a pinch at the on-threshold can produce; a fully
    /// closed pinch always articulates 127.
    public static let minVelocity: UInt8 = 40

    /// Pinch tightness → note velocity as a 0…1 Double. `pinchAmount` is the
    /// normalized thumb/index distance (0 = fully pinched); amounts at or
    /// beyond the pinch on-threshold map to minVelocity/127, fully closed to 1.0.
    /// Clamps out-of-range amounts and guards a degenerate zero threshold.
    public static func velocity(pinchAmount: Double, onThreshold: Double) -> Double {
        guard onThreshold > 0 else { return 1.0 }
        let closeness = 1 - min(max(pinchAmount / onThreshold, 0), 1)   // 1 = fully pinched
        return (Double(minVelocity) + closeness * Double(127 - minVelocity)) / 127.0
    }

    // State
    public var glideMode: GlideMode = .glide
    public private(set) var currentPitch: Double = 60
    /// Pre-quantization hand pitch (raw); glide bends from this to the held note.
    public private(set) var currentRawPitch: Double = 60
    public private(set) var isGateOpen = false
    public private(set) var currentNote: UInt8?
    public private(set) var lastVolume: UInt8 = 0
    public private(set) var lastPinchAmount: Double = 1.0
    public private(set) var vibratoActive = false
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
            // Vibrato taps the pre-quantization pitch — scale quantization is a
            // staircase and would erase sub-semitone hand oscillation.
            let raw = Double(root) + xNorm * 12 * octaves
            currentRawPitch = raw
            let pitch = MusicTheory.quantize(raw, scale: scale, root: root % 12)
            currentPitch = pitch
            let v = vibrato.process(raw, dt: dt)
            vibratoDepthCents = v.depthCents * vibratoDepthScale
            vibratoActive = v.active
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
            let p = pinch.update(r)
            pinchActive = p.isActive
            lastPinchAmount = p.amount
        }

        let baseNote = UInt8(currentPitch.rounded())
        let wantGate = pinchActive && !belowFloor

        if wantGate {
            if !isGateOpen {
                isGateOpen = true
                currentNote = baseNote
                // velocity comes from how tight the pinch was at articulation
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

        return events
    }

    private func bendSemitones() -> Double {
        let base = currentPitch.rounded()
        let frac = currentPitch - base            // ±0.5 around the held base note
        let bend = frac + vibratoDepthCents / 100
        return min(max(bend, -bendRangeSemitones), bendRangeSemitones)
    }
}