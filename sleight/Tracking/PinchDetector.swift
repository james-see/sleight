import Foundation

/// Scale-invariant pinch detection with hysteresis.
/// Pinch amount = thumb-tip(4)/index-tip(8) distance normalized by hand span
/// (wrist 0 → middle MCP 9), so the same gesture works at any camera distance.
public struct PinchDetector {
    public var onThreshold: Double   // normalized distance below which pinch fires
    public var offThreshold: Double  // must exceed onThreshold (hysteresis)

    private var isActive = false

    public init(onThreshold: Double = 0.35, offThreshold: Double = 0.42) {
        self.onThreshold = onThreshold
        self.offThreshold = offThreshold
    }

    /// Returns debounced state and the raw normalized distance (0 = fully pinched).
    public mutating func update(_ frame: HandFrame) -> (isActive: Bool, amount: Double) {
        let thumb = frame.points[Landmark.thumbTip]
        let index = frame.points[Landmark.indexTip]
        let wrist = frame.points[Landmark.wrist]
        let mcp = frame.points[Landmark.middleMCP]
        let span = max(hypot(mcp.x - wrist.x, mcp.y - wrist.y), 1e-4)
        let dist = hypot(index.x - thumb.x, index.y - thumb.y)
        let norm = dist / span
        if isActive {
            if norm > offThreshold { isActive = false }
        } else {
            if norm <= onThreshold { isActive = true }
        }
        return (isActive, norm)
    }
}