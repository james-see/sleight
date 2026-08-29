import SwiftUI

/// AR overlay: skeleton, instrument zones, pinch ring, level meter, note readout.
/// Drawn in normalized coordinates over the camera preview.
struct OverlayView: View {
    @ObservedObject var model: PipelineModel
    let pitchBand: ClosedRange<Double>
    let volumeBand: ClosedRange<Double>

    /// The model is observed, so this view re-renders on every pipeline
    /// publish and the Canvas redraws; body code keeps reading `overlay`.
    private var overlay: OverlayState { model.overlay }

    /// Hermes blue.
    static let accent = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)

    var body: some View {
        Canvas { ctx, size in
            let blue = Self.accent

            // --- pitch zone (right side) ---
            let pitchX0 = pitchBand.lowerBound * size.width
            let pitchX1 = pitchBand.upperBound * size.width
            let pitchRect = CGRect(x: pitchX0, y: 0, width: pitchX1 - pitchX0, height: size.height)
            ctx.fill(Path(pitchRect), with: .color(blue.opacity(0.08)))
            ctx.stroke(Path(pitchRect), with: .color(blue.opacity(0.25)), lineWidth: 1)

            // cursor + note name
            if let px = overlay.pitchX {
                let cx = (pitchBand.lowerBound + px * (pitchBand.upperBound - pitchBand.lowerBound)) * size.width
                var line = Path()
                line.move(to: CGPoint(x: cx, y: 0))
                line.addLine(to: CGPoint(x: cx, y: size.height))
                ctx.stroke(line, with: .color(blue.opacity(0.7)), lineWidth: 2)
                if let name = overlay.noteName {
                    ctx.draw(Text(name).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(.white),
                             at: CGPoint(x: cx, y: 36))
                }
            }

            // --- volume zone (left side) ---
            let volY0 = volumeBand.lowerBound * size.height
            let volY1 = volumeBand.upperBound * size.height
            let volRect = CGRect(x: 0, y: volY0, width: 64, height: volY1 - volY0)
            ctx.fill(Path(volRect), with: .color(blue.opacity(0.08)))
            ctx.stroke(Path(volRect), with: .color(blue.opacity(0.25)), lineWidth: 1)
            if let lvl = overlay.volumeY {
                let fillH = lvl * (volY1 - volY0)
                let fillRect = CGRect(x: 0, y: volY1 - fillH, width: 64, height: fillH)
                ctx.fill(Path(fillRect), with: .color(blue.opacity(0.5)))
            }

            // --- skeletons: proper finger chains, not one big polyline ---
            // Landmark order is wrist; thumb 1-4; index 5-8; middle 9-12;
            // ring 13-16; little 17-20. Connecting 0→1→…→20 in index order
            // draws a zigzag web across the hand.
            let chains: [[Int]] = [
                [0, 1, 2, 3, 4],          // thumb
                [0, 5, 6, 7, 8],          // index
                [0, 9, 10, 11, 12],       // middle
                [0, 13, 14, 15, 16],      // ring
                [0, 17, 18, 19, 20],      // little
                [1, 5, 9, 13, 17],        // palm (MCP webbing)
            ]
            for (_, pts) in overlay.skeleton {
                for chain in chains {
                    var path = Path()
                    for (i, idx) in chain.enumerated() where idx < pts.count {
                        let p = pts[idx]
                        let loc = CGPoint(x: p.x * size.width, y: p.y * size.height)
                        if i == 0 { path.move(to: loc) } else { path.addLine(to: loc) }
                    }
                    ctx.stroke(path, with: .color(blue.opacity(0.85)), lineWidth: 2)
                }
                for pt in pts {
                    let r: CGFloat = 3
                    let rect = CGRect(x: pt.x * size.width - r, y: pt.y * size.height - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(blue))
                }
            }

            // --- AR pads: perspective-styled rectangles with hit highlight ---
            if let pads = overlay.arPads {
                for (i, pad) in pads.enumerated() {
                    let isHit = overlay.arPadHits.contains(i)

                    // Perspective: pads lower on screen (higher Y) appear closer,
                    // so shrink them slightly toward the top for a subtle depth cue.
                    let shrinkY = 0.88 + 0.12 * (1 - pad.midY)
                    let shrinkX = 0.92 + 0.08 * (1 - pad.midY)
                    let w = pad.width * shrinkX
                    let h = pad.height * shrinkY
                    let cx = pad.midX
                    let cy = pad.midY
                    let drawRect = CGRect(
                        x: (cx - w / 2) * size.width,
                        y: (cy - h / 2) * size.height,
                        width: w * size.width,
                        height: h * size.height
                    )

                    let fillOpacity: Double = isHit ? 0.45 : 0.15
                    let strokeOpacity: Double = isHit ? 1.0 : 0.4
                    let lineWidth: CGFloat = isHit ? 3 : 1.5

                    ctx.fill(Path(drawRect), with: .color(blue.opacity(fillOpacity)))
                    ctx.stroke(Path(drawRect), with: .color(blue.opacity(strokeOpacity)), lineWidth: lineWidth)

                    // Pad number label
                    let label = Text("\(i + 1)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(isHit ? .white : blue.opacity(0.7))
                    ctx.draw(label, at: CGPoint(x: drawRect.midX, y: drawRect.midY))
                }
            }

            // --- pinch ring at thumb-index midpoint (right hand) ---
            if let pts = overlay.skeleton[.right], pts.count > Landmark.indexTip,
               let amount = overlay.pinchAmount {
                let thumb = pts[Landmark.thumbTip]
                let index = pts[Landmark.indexTip]
                let mid = CGPoint(x: (thumb.x + index.x) / 2 * size.width,
                                  y: (thumb.y + index.y) / 2 * size.height)
                // ring radius closes as pinch amount → 0; fill when active
                let closeness = min(max(1 - amount, 0), 1)
                let radius: CGFloat = 14 + 18 * CGFloat(1 - closeness)
                let ringRect = CGRect(x: mid.x - radius, y: mid.y - radius, width: radius * 2, height: radius * 2)
                ctx.stroke(Path(ellipseIn: ringRect),
                           with: .color(blue.opacity(overlay.pinchActive ? 1.0 : 0.5)),
                           lineWidth: overlay.pinchActive ? 4 : 2)
            }
        }
        .allowsHitTesting(false)
    }
}