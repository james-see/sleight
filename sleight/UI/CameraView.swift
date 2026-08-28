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
            refreshMirroring()
        }

        /// The preview connection only exists once the session has inputs — which
        /// happens later (startSession runs on appear). Setting isVideoMirrored in
        /// makeNSView silently no-ops on a nil connection. Re-apply on every
        /// layout pass instead; idempotent and cheap.
        func refreshMirroring() {
            guard let conn = preview.connection else { return }
            if conn.automaticallyAdjustsVideoMirroring {
                conn.automaticallyAdjustsVideoMirroring = false
            }
            if !conn.isVideoMirrored {
                conn.isVideoMirrored = true   // selfie view: video mirrors to match overlay coords
            }
        }
    }

    func makeNSView(context: Context) -> PreviewNSView {
        let v = PreviewNSView(frame: .zero)
        v.preview.session = session
        v.refreshMirroring()
        return v
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.refreshMirroring()
    }
}