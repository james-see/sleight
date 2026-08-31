import Foundation

/// Pure layout engine for AR pad positions in normalized camera space.
/// Pads are arranged in a grid within the right-hand pitch zone.
/// Each pad maps to a specific note determined by the scale, root, and octave.
struct ARPadLayout {
    /// Margin between pads (normalized, 0...1).
    static let padMargin: CGFloat = 0.015
    /// Horizontal band where pads live (matches default pitchBand).
    static let bandX: ClosedRange<CGFloat> = 0.55...0.95
    /// Vertical band where pads live (leaves room for volume zone).
    static let bandY: ClosedRange<CGFloat> = 0.05...0.85

    /// Compute `padCount` non-overlapping normalized rects in a grid.
    /// Pads are ordered bottom-to-top (pad 0 = lowest row = highest pitch,
    /// matching "low Y -> high pitch" convention from PolyPads).
    static func compute(padCount: Int, columns: Int = 3) -> [CGRect] {
        guard padCount > 0 else { return [] }
        let cols = max(1, min(columns, padCount))
        let rows = Int((Double(padCount) / Double(cols)).rounded(.up))
        let bandWidth = bandX.upperBound - bandX.lowerBound
        let bandHeight = bandY.upperBound - bandY.lowerBound
        let padW = (bandWidth - padMargin * CGFloat(cols - 1)) / CGFloat(cols)
        let padH = (bandHeight - padMargin * CGFloat(rows - 1)) / CGFloat(rows)

        var rects: [CGRect] = []
        for v in 0..<padCount {
            let col = v % cols
            let rowFromBottom = v / cols  // 0 = bottom row
            // Row 0 at bottom = high Y = low pitch (PolyPads convention).
            // We want pad 0 to be the first note of the scale at the bottom.
            let rowFromTop = (rows - 1) - rowFromBottom
            let x = bandX.lowerBound + CGFloat(col) * (padW + padMargin)
            let y = bandY.lowerBound + CGFloat(rowFromTop) * (padH + padMargin)
            rects.append(applyPerspective(CGRect(x: x, y: y, width: padW, height: padH)))
        }
        return rects
    }

    /// Pads lower on screen (higher Y) appear closer — shrink toward the top
    /// so draw + hit-test share the same rects.
    static func applyPerspective(_ rect: CGRect) -> CGRect {
        let shrinkY = 0.88 + 0.12 * (1 - rect.midY)
        let shrinkX = 0.92 + 0.08 * (1 - rect.midY)
        let w = rect.width * shrinkX
        let h = rect.height * shrinkY
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    /// Compute the MIDI note number for each pad given scale, root, and octave.
    /// Pads map to consecutive scale tones starting from root.
    static func padNotes(padCount: Int, scale: Scale, root: Int, octaves: Double) -> [UInt8] {
        guard padCount > 0 else { return [] }
        let intervals = scale.intervals
        if intervals.isEmpty {
            // Free / chromatic fallback: semitone steps from root
            return (0..<padCount).map { i in
                UInt8(min(127, max(0, root + i)))
            }
        }
        // Walk scale tones across octaves
        var notes: [UInt8] = []
        var octave = 0
        var idx = 0
        let maxOctave = Int(octaves)
        while notes.count < padCount {
            let interval = intervals[idx % intervals.count]
            let oct = (idx / intervals.count) + octave
            if oct > maxOctave { break }
            let note = root + interval + 12 * oct
            if note >= 0 && note <= 127 {
                notes.append(UInt8(note))
            }
            idx += 1
        }
        // If we didn't fill enough (small scale + low octaves), extend
        while notes.count < padCount {
            let lastNote = Int(notes.last ?? UInt8(root))
            let nextNote = min(127, lastNote + 1)
            notes.append(UInt8(nextNote))
        }
        return notes
    }

    /// Return the index of the pad containing the point, or nil if none.
    static func hitTest(_ point: CGPoint, pads: [CGRect]) -> Int? {
        for (i, r) in pads.enumerated() where r.contains(point) {
            return i
        }
        return nil
    }
}