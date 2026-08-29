import Foundation

/// v2.1 instrument: per-finger polyphonic pads.
///
/// Right-hand fingers become independent voices:
/// - Index (8), middle (12), ring (16), little (20) tips.
/// - Y position within `pitchBand` maps to pitch (top = low, bottom = high).
/// - Finger extension gates note on/off; retraction sends note-off.
/// - Raw Y (pre-quantization) drives per-note pitch bend.
/// - Left hand controls shared volume (CC7) — same pattern as Theremin.
/// - Each finger is a fixed voice slot (0..voiceCount-1); channel comes from
///   ChannelAllocator via voice index, not note number.
public final class PolyPads: Instrument {
    public var id: String { "poly-pads" }
    public var displayName: String { "Poly Pads" }

    // MARK: Configuration
    public var voiceCount: Int = 4          // 2–4
    public var scale: Scale = .minorPentatonic
    public var root: Int = 60
    public var octaves: Double = 2
    public var pitchBand: ClosedRange<Double> = 0.55...0.95
    public var volumeBand: ClosedRange<Double> = 0.1...0.7
    public var defaultVolume: UInt8 = 100

    /// AR pad layout (normalized rects). When set, finger Y snaps to the
    /// center Y of whichever pad the finger tip is inside, producing a stable
    /// quantized note. When nil, continuous Y-to-pitch mapping is used.
    public var padLayout: [CGRect]? = nil

    /// Extension threshold (0…1). Finger is "extended" when the tip-to-MCP
    /// distance, normalized by the palm size, exceeds this value.
    public var extensionThreshold: Double = 0.35

    // MARK: State (per-voice)
    private var voiceNotes: [Int: UInt8] = [:]     // voice → current note
    private var voiceGateOpen: [Int: Bool] = [:]   // voice → gate state
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

        // ---- per-finger voices ----
        if let r = right {
            let palmSize = palmSize(of: r)
            for v in 0..<voiceCount {
                let tipIdx = Self.fingerTips[v]
                let mcpIdx = Self.fingerMCPs[v]
                let tip = r.points[tipIdx]
                let mcp = r.points[mcpIdx]
                guard tip.confidence > 0.5, mcp.confidence > 0.5 else { continue }

                let extensionRatio = distance(tip, mcp) / max(palmSize, 0.001)
                let extended = extensionRatio >= extensionThreshold
                let prevOpen = voiceGateOpen[v] ?? false

                if extended {
                    // Determine Y for pitch: snap to pad center Y when finger is
                    // inside an AR pad rect; otherwise use continuous finger Y.
                    let snapY: Double
                    if let layout = padLayout,
                       let hitIdx = ARPadLayout.hitTest(
                           CGPoint(x: tip.x, y: tip.y), pads: layout
                       ) {
                        snapY = Double(layout[hitIdx].midY)
                    } else {
                        snapY = tip.y
                    }
                    let yNorm = min(max((snapY - pitchBand.lowerBound) / (pitchBand.upperBound - pitchBand.lowerBound), 0), 1)
                    let rawPitch = Double(root) + yNorm * 12 * octaves
                    let pitch = MusicTheory.quantize(rawPitch, scale: scale, root: root % 12)
                    let note = UInt8(pitch.rounded())

                    if !prevOpen {
                        // Note on
                        let vel = min(max(extensionRatio, 0), 1)
                        events.append(MIDIEvent(kind: .noteOn(note: note, velocity: vel, channel: UInt8(v + 1)), timestamp: t))
                        voiceGateOpen[v] = true
                        voiceNotes[v] = note
                    } else {
                        // Continuous: per-note bend from raw Y
                        let bend = rawPitch - Double(note)
                        events.append(MIDIEvent(kind: .perNotePitchBendSemitones(note: note, bend, channel: UInt8(v + 1)), timestamp: t))
                    }
                } else if prevOpen {
                    // Note off
                    if let note = voiceNotes[v] {
                        events.append(MIDIEvent(kind: .noteOff(note: note, channel: UInt8(v + 1)), timestamp: t))
                    }
                    voiceGateOpen[v] = false
                    voiceNotes.removeValue(forKey: v)
                }
            }
        } else {
            // Right hand lost: close all voices
            for v in 0..<voiceCount {
                if voiceGateOpen[v] == true {
                    if let note = voiceNotes[v] {
                        events.append(MIDIEvent(kind: .noteOff(note: note, channel: UInt8(v + 1)), timestamp: t))
                    }
                    voiceGateOpen[v] = false
                }
            }
            voiceNotes.removeAll()
        }

        if volume != lastVolume || !events.isEmpty {
            events.append(MIDIEvent(kind: .cc(7, volume), timestamp: t))
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
