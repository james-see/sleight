import Foundation

/// Pure layout engine for AR pad positions in normalized camera space.
/// Pads are arranged in a grid (default 2 columns) within the right-hand
/// pitch zone. High Y -> low pitch, low Y -> high pitch (same as PolyPads).
struct ARPadLayout {
    /// Margin between pads (normalized, 0...1).
    static let padMargin: CGFloat = 0.02
    /// Horizontal band where pads live (matches default pitchBand).
    static let bandX: ClosedRange<CGFloat> = 0.55...0.95

    /// Compute `voiceCount` non-overlapping normalized rects in a grid.
    /// Pads are ordered bottom-to-top (pad 0 = lowest Y = highest pitch,
    /// matching PolyPads voice 0 = index finger = first note).
    static func compute(voiceCount: Int, columns: Int = 2) -> [CGRect] {
        guard voiceCount > 0 else { return [] }
        let rows = Int((Double(voiceCount) / Double(columns)).rounded(.up))
        let bandWidth = bandX.upperBound - bandX.lowerBound
        let padW = (bandWidth - padMargin * CGFloat(columns - 1)) / CGFloat(columns)
        let padH = (1.0 - padMargin * CGFloat(rows - 1)) / CGFloat(rows)

        var rects: [CGRect] = []
        for v in 0..<voiceCount {
            let col = v % columns
            let rowFromBottom = v / columns  // 0 = bottom row
            // In normalized top-down space, row 0 (bottom) = high Y value
            // because PolyPads maps low Y -> high pitch. But we want pad 0
            // (index finger) at a comfortable mid-high position. We reverse:
            // row 0 at top (low Y = high pitch), matching "low Y -> high pitch".
            let rowFromTop = (rows - 1) - rowFromBottom
            let x = bandX.lowerBound + CGFloat(col) * (padW + padMargin)
            let y = CGFloat(rowFromTop) * (padH + padMargin)
            rects.append(CGRect(x: x, y: y, width: padW, height: padH))
        }
        return rects
    }

    /// Return the index of the pad containing the point, or nil if none.
    static func hitTest(_ point: CGPoint, pads: [CGRect]) -> Int? {
        for (i, r) in pads.enumerated() where r.contains(point) {
            return i
        }
        return nil
    }
}