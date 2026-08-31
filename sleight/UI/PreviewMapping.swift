import Foundation
import CoreGraphics

/// Maps Vision-normalized coordinates (0…1, already mirrored/flipped) through
/// the same aspect-fill crop that `AVCaptureVideoPreviewLayer` applies so the
/// overlay lands on the visible camera image.
enum PreviewMapping {
    /// Point in view-normalized 0…1. Identity when either size is empty.
    static func aspectFill(point: CGPoint, imageSize: CGSize, viewSize: CGSize) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            return point
        }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offset = CGPoint(
            x: (viewSize.width - scaled.width) / 2,
            y: (viewSize.height - scaled.height) / 2
        )
        return CGPoint(
            x: (point.x * scaled.width + offset.x) / viewSize.width,
            y: (point.y * scaled.height + offset.y) / viewSize.height
        )
    }

    static func aspectFill(rect: CGRect, imageSize: CGSize, viewSize: CGSize) -> CGRect {
        let a = aspectFill(point: CGPoint(x: rect.minX, y: rect.minY), imageSize: imageSize, viewSize: viewSize)
        let b = aspectFill(point: CGPoint(x: rect.maxX, y: rect.maxY), imageSize: imageSize, viewSize: viewSize)
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
}
