import SwiftUI

/// AR overlay: skeleton, instrument zones, pinch ring, level meter, note readout.
/// Drawn in normalized coordinates over the camera preview, mapped through
/// the same aspect-fill crop as the preview layer.
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
            let img = overlay.imageSize

            func mapPoint(_ p: CGPoint) -> CGPoint {
                let n = PreviewMapping.aspectFill(point: p, imageSize: img, viewSize: size)
                return CGPoint(x: n.x * size.width, y: n.y * size.height)
            }
            func mapRect(_ r: CGRect) -> CGRect {
                let n = PreviewMapping.aspectFill(rect: r, imageSize: img, viewSize: size)
                return CGRect(
                    x: n.minX * size.width,
                    y: n.minY * size.height,
                    width: n.width * size.width,
                    height: n.height * size.height
                )
            }

            // --- pitch zone (right side) ---
            let pitchRect = mapRect(CGRect(
                x: pitchBand.lowerBound, y: 0,
                width: pitchBand.upperBound - pitchBand.lowerBound, height: 1
            ))
            ctx.fill(Path(pitchRect), with: .color(blue.opacity(0.08)))
            ctx.stroke(Path(pitchRect), with: .color(blue.opacity(0.25)), lineWidth: 1)

            // cursor + note name
            if let px = overlay.pitchX {
                let nx = pitchBand.lowerBound + px * (pitchBand.upperBound - pitchBand.lowerBound)
                let top = mapPoint(CGPoint(x: nx, y: 0))
                let bot = mapPoint(CGPoint(x: nx, y: 1))
                var line = Path()
                line.move(to: top)
                line.addLine(to: bot)
                ctx.stroke(line, with: .color(blue.opacity(0.7)), lineWidth: 2)
                if let name = overlay.noteName {
                    ctx.draw(Text(name).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(.white),
                             at: CGPoint(x: top.x, y: 36))
                }
            }

            // --- volume zone (left side) ---
            let volTop = mapPoint(CGPoint(x: 0, y: volumeBand.lowerBound))
            let volBot = mapPoint(CGPoint(x: 0, y: volumeBand.upperBound))
            let volRect = CGRect(x: volTop.x, y: volTop.y, width: 64, height: volBot.y - volTop.y)
            ctx.fill(Path(volRect), with: .color(blue.opacity(0.08)))
            ctx.stroke(Path(volRect), with: .color(blue.opacity(0.25)), lineWidth: 1)
            if let lvl = overlay.volumeY {
                let fillH = lvl * volRect.height
                let fillRect = CGRect(x: volRect.minX, y: volRect.maxY - fillH, width: volRect.width, height: fillH)
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
                        let loc = mapPoint(pts[idx])
                        if i == 0 { path.move(to: loc) } else { path.addLine(to: loc) }
                    }
                    ctx.stroke(path, with: .color(blue.opacity(0.85)), lineWidth: 2)
                }
                for pt in pts {
                    let r: CGFloat = 3
                    let loc = mapPoint(pt)
                    let rect = CGRect(x: loc.x - r, y: loc.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(blue))
                }
            }

            // --- AR pads: note labels, hover vs press highlighting ---
            if let pads = overlay.arPads {
                let padNotes = overlay.arPadNotes
                let pressed = overlay.arPadsPressed
                let hovered = overlay.arPadHits

                for (i, pad) in pads.enumerated() {
                    let isPressed = pressed.contains(i)
                    let isHovered = hovered.contains(i) && !isPressed
                    let drawRect = mapRect(pad)

                    // Opacity/color only — stroke and type size stay put so
                    // highlights don't shimmer when the gate flickers.
                    let fillOpacity: Double = isPressed ? 0.45 : (isHovered ? 0.22 : 0.10)
                    let strokeOpacity: Double = isPressed ? 1.0 : (isHovered ? 0.6 : 0.3)
                    let borderColor: Color = isPressed ? .white : blue

                    ctx.fill(Path(drawRect), with: .color(blue.opacity(fillOpacity)))
                    ctx.stroke(Path(drawRect), with: .color(borderColor.opacity(strokeOpacity)), lineWidth: 1.5)

                    let noteName: String
                    if i < padNotes.count {
                        noteName = MusicTheory.noteName(Int(padNotes[i]))
                    } else {
                        noteName = "\(i + 1)"
                    }

                    let labelColor: Color = isPressed ? .white : (isHovered ? .white.opacity(0.9) : blue.opacity(0.6))
                    ctx.draw(
                        Text(noteName)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
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
                let mid = mapPoint(CGPoint(x: (thumb.x + index.x) / 2, y: (thumb.y + index.y) / 2))
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
