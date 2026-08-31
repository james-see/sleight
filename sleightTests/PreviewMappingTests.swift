import XCTest
@testable import sleight

final class PreviewMappingTests: XCTestCase {
    func testIdentityWhenAspectMatches() {
        let image = CGSize(width: 1920, height: 1080)
        let view = CGSize(width: 1920, height: 1080)
        let p = PreviewMapping.aspectFill(point: CGPoint(x: 0.25, y: 0.75), imageSize: image, viewSize: view)
        XCTAssertEqual(p.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.75, accuracy: 1e-9)
    }

    func testIdentityWhenImageSizeMissing() {
        let p = PreviewMapping.aspectFill(
            point: CGPoint(x: 0.4, y: 0.6),
            imageSize: .zero,
            viewSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(p.x, 0.4, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.6, accuracy: 1e-9)
    }

    func testCenterStaysCenteredWhenViewIsTaller() {
        let image = CGSize(width: 1920, height: 1080)
        let view = CGSize(width: 1000, height: 1400)
        let p = PreviewMapping.aspectFill(point: CGPoint(x: 0.5, y: 0.5), imageSize: image, viewSize: view)
        XCTAssertEqual(p.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(p.y, 0.5, accuracy: 1e-6)
    }

    /// 16:9 image into a square view: fill on height, crop left/right.
    func testHorizontalCropOnSquareView() {
        let image = CGSize(width: 1920, height: 1080)
        let view = CGSize(width: 1000, height: 1000)
        let left = PreviewMapping.aspectFill(point: CGPoint(x: 0, y: 0.5), imageSize: image, viewSize: view)
        let right = PreviewMapping.aspectFill(point: CGPoint(x: 1, y: 0.5), imageSize: image, viewSize: view)
        XCTAssertLessThan(left.x, 0, "left edge of buffer is cropped off-screen")
        XCTAssertGreaterThan(right.x, 1, "right edge of buffer is cropped off-screen")
        let mid = PreviewMapping.aspectFill(point: CGPoint(x: 0.5, y: 0.5), imageSize: image, viewSize: view)
        XCTAssertEqual(mid.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(mid.y, 0.5, accuracy: 1e-6)
    }

    func testRectMapsThroughSameTransform() {
        let image = CGSize(width: 1920, height: 1080)
        let view = CGSize(width: 1000, height: 1000)
        let r = CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.2)
        let mapped = PreviewMapping.aspectFill(rect: r, imageSize: image, viewSize: view)
        let a = PreviewMapping.aspectFill(point: CGPoint(x: r.minX, y: r.minY), imageSize: image, viewSize: view)
        let b = PreviewMapping.aspectFill(point: CGPoint(x: r.maxX, y: r.maxY), imageSize: image, viewSize: view)
        XCTAssertEqual(mapped.minX, a.x, accuracy: 1e-9)
        XCTAssertEqual(mapped.minY, a.y, accuracy: 1e-9)
        XCTAssertEqual(mapped.maxX, b.x, accuracy: 1e-9)
        XCTAssertEqual(mapped.maxY, b.y, accuracy: 1e-9)
    }
}
