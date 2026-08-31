import Foundation

/// v2.4 instrument: AR pad player.
///
/// When AR pads are enabled (default), each pad maps to a specific note.
/// A note fires when a finger tip is inside a pad rect AND curled, and the
/// press has been held for `minPressDuration` (a 16th/32nd at the session BPM).
/// Shorter presses are discarded as misfires. Release needs two consecutive
/// frames of extend-or-leave so a one-frame Vision flicker does not click.
///
/// Up to 4 fingers can play simultaneously (index, middle, ring, little).
/// Each finger is assigned to whichever pad it's currently inside. A finger
/// can only play one pad at a time, and a pad can only be played by one finger.
///
/// When AR pads are disabled, falls back to the original extension-based gate
/// with continuous Y-to-pitch mapping (v2.1 behavior).
///
/// Left hand controls shared volume (CC7) — same pattern as Theremin.
public final class PolyPads: Instrument {
    public var id: String { "poly-pads" }
    public var displayName: String { "Poly Pads" }

    // MARK: Configuration
    public var voiceCount: Int = 4          // legacy: 2-4 for extension mode
    public var padCount: Int = 12           // v2.2: number of AR pads
    public var scale: Scale = .minorPentatonic
    public var root: Int = 60
    public var octaves: Double = 2
    public var pitchBand: ClosedRange<Double> = 0.55...0.95
    public var volumeBand: ClosedRange<Double> = 0.1...0.7
    public var defaultVolume: UInt8 = 100

    /// AR pad layout (normalized rects). When set, pads are the primary play mode.
    public var padLayout: [CGRect]? = nil
    /// Pre-computed notes for each pad (set alongside padLayout).
    public var padNotes: [UInt8]? = nil

    /// Extension threshold (0-1). Finger is "extended" when tip-to-MCP distance,
    /// normalized by palm size, exceeds this. Used for legacy extension gate.
    public var extensionThreshold: Double = 0.35

    /// Press thresholds for AR pad mode (0-1). A pad fires only when the finger
    /// is inside the pad rect AND curled (extensionRatio below pressThreshold).
    /// It releases when the finger extends back above releaseThreshold.
    /// The gap prevents flicker. With a flat hand (all fingers extended),
    /// extensionRatio is high (~0.5+) so no pads fire — you must curl a
    /// finger toward the pad to press it.
    public var pressThreshold: Double = 0.30
    public var releaseThreshold: Double = 0.38
    /// Hold this long (seconds) before emitting note-on. Default = 32nd @ 120 BPM.
    public var minPressDuration: Double = NoteSubdivision.duration(bpm: 120, subdivision: .thirtySecond)
    /// Consecutive release-condition frames before note-off.
    public var releaseDebounceFrames: Int = 2

    // MARK: State (per-pad)
    /// Which pads are currently sounding (pad index -> note). Read-only access
    /// for the overlay to highlight pressed pads.
    private(set) var activePads: [Int: UInt8] = [:]
    /// Which fingers are currently inside a pad (finger index -> pad index).
    private(set) var fingerPadAssignment: [Int: Int] = [:]
    private var pendingPress: [Int: (pad: Int, start: Double)] = [:]
    private var releaseFrames: [Int: Int] = [:]
    private var lastVolume: UInt8 = 0
    private var clock: Double = 0

    /// Landmark indices for the finger tips we use (index, middle, ring, little).
    private static let fingerTips = [8, 12, 16, 20]
    /// MCP joints corresponding to the tips above.
    private static let fingerMCPs  = [5, 9, 13, 17]

    public init() {}

    public func update(hands: [HandFrame], dt: Double) -> [MIDIEvent] {
        clock += dt
        var events: [MIDIEvent] = []
        let t = clock

        let right = hands.first { $0.side == .right }
        let left  = hands.first { $0.side == .left }

        // ---- volume (left wrist y, same as Theremin) ----
        var volume: UInt8
        if let l = left {
            let y = l.points[Landmark.wrist].y
            if y <= volumeBand.lowerBound {
                volume = 127
            } else if y >= volumeBand.upperBound {
                volume = 0
            } else {
                let n = 1 - (y - volumeBand.lowerBound) / (volumeBand.upperBound - volumeBand.lowerBound)
                volume = UInt8((n * 127).rounded())
            }
            lastVolume = volume
        } else {
            volume = lastVolume == 0 ? defaultVolume : lastVolume
        }

        // ---- pad-based play mode ----
        if let layout = padLayout, let notes = padNotes, !layout.isEmpty {
            events.append(contentsOf: processPadMode(
                right: right, layout: layout, notes: notes, t: t
            ))
        }
        // ---- legacy extension-based play mode (no pads) ----
        else if let r = right {
            events.append(contentsOf: processExtensionMode(
                right: r, t: t
            ))
        } else {
            // Right hand lost: close everything
            for (_, note) in activePads {
                events.append(MIDIEvent(kind: .noteOff(note: note, channel: 0), timestamp: t))
            }
            activePads.removeAll()
            fingerPadAssignment.removeAll()
            pendingPress.removeAll()
            releaseFrames.removeAll()
        }

        if volume != lastVolume || !events.isEmpty {
            events.append(MIDIEvent(kind: .cc(7, volume), timestamp: t))
        }
        if left == nil { lastVolume = volume }

        return events
    }

    // MARK: Pad mode (v2.2)

    private func processPadMode(right: HandFrame?, layout: [CGRect], notes: [UInt8], t: Double) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        guard let r = right else {
            // Hand lost: release all active pads
            for (_, note) in activePads {
                events.append(MIDIEvent(kind: .noteOff(note: note, channel: 0), timestamp: t))
            }
            activePads.removeAll()
            fingerPadAssignment.removeAll()
            pendingPress.removeAll()
            releaseFrames.removeAll()
            return events
        }

        let palmSize = palmSize(of: r)
        let fingerCount = min(Self.fingerTips.count, 4)
        var padsHeld: Set<Int> = []

        for f in 0..<fingerCount {
            let tipIdx = Self.fingerTips[f]
            let mcpIdx = Self.fingerMCPs[f]
            let tip = r.points[tipIdx]
            let mcp = r.points[mcpIdx]
            guard tip.confidence > 0.5, mcp.confidence > 0.5 else { continue }

            let extensionRatio = distance(tip, mcp) / max(palmSize, 0.001)
            let tipPoint = CGPoint(x: tip.x, y: tip.y)
            let padIdx = ARPadLayout.hitTest(tipPoint, pads: layout)
            let curled = extensionRatio < pressThreshold
            let wantPress = padIdx != nil && curled
            let wantRelease = {
                if fingerPadAssignment[f] != nil {
                    if padIdx == nil { return true }
                    return extensionRatio > releaseThreshold
                }
                return false
            }()

            if wantPress, let padIdx {
                releaseFrames[f] = 0
                if fingerPadAssignment[f] == padIdx {
                    padsHeld.insert(padIdx)
                    continue
                }
                if let pending = pendingPress[f], pending.pad == padIdx {
                    if t - pending.start >= minPressDuration {
                        events.append(contentsOf: confirmPress(finger: f, padIdx: padIdx, notes: notes, t: t))
                        padsHeld.insert(padIdx)
                    }
                } else {
                    pendingPress[f] = (pad: padIdx, start: t)
                    if minPressDuration <= 0 {
                        events.append(contentsOf: confirmPress(finger: f, padIdx: padIdx, notes: notes, t: t))
                        padsHeld.insert(padIdx)
                    }
                }
            } else {
                pendingPress.removeValue(forKey: f)
                if wantRelease {
                    let count = (releaseFrames[f] ?? 0) + 1
                    releaseFrames[f] = count
                    if count >= max(releaseDebounceFrames, 1) {
                        events.append(contentsOf: releaseFinger(f, t: t))
                    } else if let pad = fingerPadAssignment[f] {
                        padsHeld.insert(pad)
                    }
                } else if let pad = fingerPadAssignment[f] {
                    releaseFrames[f] = 0
                    padsHeld.insert(pad)
                }
            }
        }

        for (padIdx, note) in activePads {
            if !padsHeld.contains(padIdx), !fingerPadAssignment.values.contains(padIdx) {
                events.append(MIDIEvent(kind: .noteOff(note: note, channel: 0), timestamp: t))
                activePads.removeValue(forKey: padIdx)
            }
        }

        return events
    }

    private func confirmPress(finger: Int, padIdx: Int, notes: [UInt8], t: Double) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        if let prevPad = fingerPadAssignment[finger], prevPad != padIdx {
            events.append(contentsOf: releasePad(prevPad, t: t))
            if fingerPadAssignment[finger] == prevPad {
                fingerPadAssignment.removeValue(forKey: finger)
            }
        }
        let note = notes[padIdx]
        events.append(MIDIEvent(kind: .noteOn(note: note, velocity: 0.8, channel: 0), timestamp: t))
        activePads[padIdx] = note
        fingerPadAssignment[finger] = padIdx
        pendingPress.removeValue(forKey: finger)
        return events
    }

    private func releaseFinger(_ finger: Int, t: Double) -> [MIDIEvent] {
        guard let pad = fingerPadAssignment[finger] else { return [] }
        fingerPadAssignment.removeValue(forKey: finger)
        releaseFrames.removeValue(forKey: finger)
        pendingPress.removeValue(forKey: finger)
        return releasePad(pad, t: t)
    }

    private func releasePad(_ padIdx: Int, t: Double) -> [MIDIEvent] {
        guard let note = activePads.removeValue(forKey: padIdx) else { return [] }
        return [MIDIEvent(kind: .noteOff(note: note, channel: 0), timestamp: t)]
    }

    // MARK: Legacy extension mode (v2.1 fallback)

    private func processExtensionMode(right: HandFrame, t: Double) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        let palmSize = palmSize(of: right)

        for v in 0..<voiceCount {
            let tipIdx = Self.fingerTips[v]
            let mcpIdx = Self.fingerMCPs[v]
            let tip = right.points[tipIdx]
            let mcp = right.points[mcpIdx]
            guard tip.confidence > 0.5, mcp.confidence > 0.5 else { continue }

            let extensionRatio = distance(tip, mcp) / max(palmSize, 0.001)
            let extended = extensionRatio >= extensionThreshold

            if extended {
                let yNorm = min(max((tip.y - pitchBand.lowerBound) / (pitchBand.upperBound - pitchBand.lowerBound), 0), 1)
                let rawPitch = Double(root) + yNorm * 12 * octaves
                let pitch = MusicTheory.quantize(rawPitch, scale: scale, root: root % 12)
                let note = UInt8(pitch.rounded())

                if activePads[v] == nil {
                    let vel = min(max(extensionRatio, 0), 1)
                    events.append(MIDIEvent(kind: .noteOn(note: note, velocity: vel, channel: UInt8(v + 1)), timestamp: t))
                    activePads[v] = note
                } else {
                    let bend = rawPitch - Double(note)
                    events.append(MIDIEvent(kind: .perNotePitchBendSemitones(note: note, bend, channel: UInt8(v + 1)), timestamp: t))
                }
            } else if activePads[v] != nil {
                if let note = activePads[v] {
                    events.append(MIDIEvent(kind: .noteOff(note: note, channel: UInt8(v + 1)), timestamp: t))
                }
                activePads.removeValue(forKey: v)
            }
        }

        return events
    }

    // MARK: Helpers

    private func palmSize(of hand: HandFrame) -> Double {
        let wrist = hand.points[Landmark.wrist]
        let middleMCP = hand.points[Landmark.middleMCP]
        guard wrist.confidence > 0.5, middleMCP.confidence > 0.5 else { return 0.1 }
        return distance(wrist, middleMCP)
    }

    private func distance(_ a: LandmarkPoint, _ b: LandmarkPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx*dx + dy*dy)
    }
}