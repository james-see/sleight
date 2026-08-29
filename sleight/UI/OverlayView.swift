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

            // --- AR pads: note labels, hover vs press highlighting ---
            if let pads = overlay.arPads {
                let padNotes = overlay.arPadNotes ?? []
                let pressed = overlay.arPadsPressed
                let hovered = overlay.arPadHits

                for (i, pad) in pads.enumerated() {
                    let isPressed = pressed.contains(i)
                    let isHovered = hovered.contains(i) && !isPressed

                    let drawRect = CGRect(
                        x: pad.minX * size.width,
                        y: pad.minY * size.height,
                        width: pad.width * size.width,
                        height: pad.height * size.height
                    )

                    // Fill: pressed = bright, hovered = medium, idle = dim
                    let fillOpacity: Double = isPressed ? 0.45 : (isHovered ? 0.22 : 0.10)
                    let strokeOpacity: Double = isPressed ? 1.0 : (isHovered ? 0.6 : 0.3)
                    let lineWidth: CGFloat = isPressed ? 3 : 1.5
                    let borderColor: Color = isPressed ? .white : blue

                    ctx.fill(Path(drawRect), with: .color(blue.opacity(fillOpacity)))
                    ctx.stroke(Path(drawRect), with: .color(borderColor.opacity(strokeOpacity)), lineWidth: lineWidth)

                    // Note name label
                    let noteName: String
                    if i < padNotes.count {
                        noteName = MusicTheory.noteName(Int(padNotes[i]))
                    } else {
                        noteName = "\(i + 1)"
                    }

                    let labelColor: Color = isPressed ? .white : (isHovered ? .white.opacity(0.9) : blue.opacity(0.6))
                    let fontSize: CGFloat = isPressed ? 16 : 13
                    ctx.draw(
                        Text(noteName)
                            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(labelColor),
                        at: CGPoint(x: drawRect.midX, y: drawRect.midY)
                    )
                }
            }

            // --- pinch ring at thumb-index midpoint (right hand) ---
            if let pts = overlay.skeleton[.right], pts.count > Landmark.indexTip,
               let amount = overlay.pinchAmount {
                let thumb = pts[Landmark.thumbTip]
                let index = pts[Landmark.indexTip]
                let mid = CGPoint(x: (thumb.x + index.x) / 2 * size.width,
                                  y: (thumb.y + index.y) / 2 * size.height)
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