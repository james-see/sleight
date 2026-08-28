import AVFoundation
import CoreVideo

enum CaptureError: Error {
    case permissionDenied
    case noCamera
    case configurationFailed(String)
}

final class CaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called on the capture queue for every delivered frame.
    var onFrame: ((CVPixelBuffer) -> Void)?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "us.jamescampbell.sleight.capture", qos: .userInteractive)
    private(set) var isRunning = false

    func start() throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            try reallyStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self, granted else { return }
                DispatchQueue.main.async {
                    do { try self.reallyStart() } catch { /* surfaced via isRunning staying false */ }
                }
            }
        default:
            throw CaptureError.permissionDenied
        }
    }

    func stop() {
        session.stopRunning()
        isRunning = false
    }

    /// Chooses the frame rate to lock the camera to. Prefers 60 fps, but clamps to the
    /// device's supported range — FaceTime HD / built-in cameras often cap at 30 fps, and
    /// asking for 60 throws NSInvalidArgumentException at startup.
    static func targetFrameRate(preference: Double = 60, ranges: [(min: Double, max: Double)]) -> Int32 {
        if ranges.contains(where: { $0.min <= preference && $0.max >= preference }) {
            return Int32(preference)
        }
        let best = ranges.map { $0.max }.max() ?? preference
        let clamped = Int32(best.rounded(.down))
        return max(clamped, 1)
    }

    private func reallyStart() throws {
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else { throw CaptureError.noCamera }
        try cam.lockForConfiguration()
        let supported = cam.activeFormat.videoSupportedFrameRateRanges.map { (min: $0.minFrameRate, max: $0.maxFrameRate) }
        let duration = CMTime(value: 1, timescale: Self.targetFrameRate(ranges: supported))
        cam.activeVideoMinFrameDuration = duration
        cam.activeVideoMaxFrameDuration = duration
        cam.unlockForConfiguration()

        session.beginConfiguration()
        session.sessionPreset = .high

        let input = try AVCaptureDeviceInput(device: cam)
        guard session.canAddInput(input) else { throw CaptureError.configurationFailed("cannot add camera input") }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.alwaysDiscardsLateVideoFrames = true   // never queue — stale frames are useless
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CaptureError.configurationFailed("cannot add video output") }
        session.addOutput(output)
        session.commitConfiguration()

        session.startRunning()
        isRunning = session.isRunning
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = sampleBuffer.imageBuffer else { return }
        onFrame?(pb)
    }

    /// Exposed for CameraPreview (Task 11).
    var captureSession: AVCaptureSession { session }
}