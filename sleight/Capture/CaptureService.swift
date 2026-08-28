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

    private func reallyStart() throws {
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else { throw CaptureError.noCamera }
        try cam.lockForConfiguration()
        cam.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        cam.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
        cam.unlockForConfiguration()

        session.beginConfiguration()
        defer { session.commitConfiguration() }
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