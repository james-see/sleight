import SwiftUI

/// Top HUD strip: tracking state, fps, dropped frames, current note, vibrato.
struct HUDView: View {
    @ObservedObject var model: PipelineModel

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(model.overlay.trackingActive ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            Text(model.overlay.trackingActive ? "tracking" : "no hands")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(String(format: "%.0f fps", model.overlay.fps))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("drops \(model.overlay.droppedFrames)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            if let note = model.overlay.noteName {
                Text(note)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(OverlayView.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}