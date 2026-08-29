import Foundation

/// v2.2 instrument: AR pad player.
///
/// When AR pads are enabled (default), each pad maps to a specific note.
/// A note fires when a finger tip enters a pad rect; it releases when the
/// finger tip leaves the pad. This is the "air tap" model — the most natural
/// and repeatable interaction for 2D hand tracking. No curl or depth detection
/// needed: the pad rect IS the key.
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

    // MARK: State (per-pad)
    /// Which pads are currently sounding (pad index -> note). Read-only access
    /// for the overlay to highlight pressed pads.
    private(set) var activePads: [Int: UInt8] = [:]
    /// Which fingers are currently inside a pad (finger index -> pad index).
    private(set) var fingerPadAssignment: [Int: Int] = [:]
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
            return events
        }

        let palmSize = palmSize(of: r)
        let fingerCount = min(Self.fingerTips.count, 4)  // index, middle, ring, little

        // Track which pads are hit this frame (finger inside rect AND curled)
        var padsHitThisFrame: Set<Int> = []

        for f in 0..<fingerCount {
            let tipIdx = Self.fingerTips[f]
            let mcpIdx = Self.fingerMCPs[f]
            let tip = r.points[tipIdx]
            let mcp = r.points[mcpIdx]
            guard tip.confidence > 0.5, mcp.confidence > 0.5 else { continue }

            let extensionRatio = distance(tip, mcp) / max(palmSize, 0.001)
            let tipPoint = CGPoint(x: tip.x, y: tip.y)

            // Which pad is this finger hovering over?
            guard let padIdx = ARPadLayout.hitTest(tipPoint, pads: layout) else {
                // Finger not inside any pad — if it was pressing one, release
                if let prevPad = fingerPadAssignment[f] {
                    if let note = activePads[prevPad] {
                        events.append(MIDIEvent(kind: .noteOff(note: note, channel: 0), timestamp: t))
                    }
                    activePads.removeValue(forKey: prevPad)
                    fingerPadAssignment.removeValue(forKey: f)
                }
                continue
            }

            let wasPressing = fingerPadAssignment[f] == padIdx

            if !wasPressing {
                // Not yet pressing this pad: check if finger curls enough to press
                if extensionRatio < pressThreshold {
                    // Press! Finger is inside the pad AND curled
                    // Release any previous pad this finger was on
                    if let prevPad = fingerPadAssignment[f], prevPad != padIdx {
                        if let prevNote = activePads[prevPad] {
                            events.append(MIDIEvent(kind: .noteOff(note: prevNote, channel: 0), timestamp: t))
                        }
                        activePads.removeValue(forKey: prevPad)
                    }
                    padsHitThisFrame.insert(padIdx)
                    let note = notes[padIdx]
                    events.append(MIDIEvent(kind: .noteOn(note: note, velocity: 0.8, channel: 0), timestamp: t))
                    activePads[padIdx] = note
                    fingerPadAssignment[f] = padIdx
                }
                // else: hovering over pad but finger is extended (flat hand) — no press
            } else {
                // Already pressing: release if finger extends OR leaves the pad
                if extensionRatio > releaseThreshold {
                    // Finger extended back — release
                    let note = notes[padIdx]
                    events.append(MIDIEvent(kind: .noteOff(note: note, channel: 0), timestamp: t))
                    activePads.removeValue(forKey: padIdx)
                    fingerPadAssignment.removeValue(forKey: f)
                } else {
                    // Still pressing (curled + inside pad)
                    padsHitThisFrame.insert(padIdx)
                }
            }
        }

        // Release any active pads that no longer have a finger inside them
        for (padIdx, note) in activePads {
            if !padsHitThisFrame.contains(padIdx) {
                let stillAssigned = fingerPadAssignment.values.contains(padIdx)
                if !stillAssigned {
                    events.append(MIDIEvent(kind: .noteOff(note: note, channel: 0), timestamp: t))
                    activePads.removeValue(forKey: padIdx)
                }
            }
        }

        return events
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