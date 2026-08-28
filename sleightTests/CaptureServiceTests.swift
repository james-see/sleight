import XCTest
@testable import sleight

final class CaptureServiceTests: XCTestCase {
    func testPrefersSixtyWhenSupported() {
        XCTAssertEqual(CaptureService.targetFrameRate(ranges: [(min: 15, max: 60)]), 60)
    }

    func testClampsToThirtyOnFaceTimeHDCamera() {
        // James's built-in camera: 15–30 fps only. Asking for 60 crashed the app.
        XCTAssertEqual(CaptureService.targetFrameRate(ranges: [(min: 15, max: 30)]), 30)
    }

    func testPicksBestRangeWhenMultiple() {
        XCTAssertEqual(CaptureService.targetFrameRate(ranges: [(min: 15, max: 30), (min: 15, max: 60)]), 60)
    }

    func testFixedRateCamera() {
        XCTAssertEqual(CaptureService.targetFrameRate(ranges: [(min: 24, max: 24)]), 24)
    }

    func testRoundsDownFractionalMax() {
        XCTAssertEqual(CaptureService.targetFrameRate(ranges: [(min: 15, max: 29.97)]), 29)
    }

    func testEmptyRangesFallsBackToPreference() {
        XCTAssertEqual(CaptureService.targetFrameRate(ranges: []), 60)
    }
}