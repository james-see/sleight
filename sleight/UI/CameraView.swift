import SwiftUI
import AVFoundation

/// AVCaptureVideoPreviewLayer host — the live mirrored camera feed.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    final class PreviewNSView: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        private var previewLayer: CALayer { preview }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = preview
            preview.videoGravity = .resizeAspectFill
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

        override func layout() {
            super.layout()
            preview.frame = bounds
        }
    }

    func makeNSView(context: Context) -> PreviewNSView {
        let v = PreviewNSView(frame: .zero)
        v.preview.session = session
        if let conn = v.preview.connection {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true   // selfie view: video mirrors to match overlay coords
        }
        return v
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}
}