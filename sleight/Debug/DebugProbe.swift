import Foundation

/// Cross-thread diagnostic snapshot for the "no hands" state.
/// Written from the capture queue, read from the main thread under a lock.
final class DebugProbe {
    static let shared = DebugProbe()
    private let lock = NSLock()
    private var _device = "—"
    private var _frameW = 0
    private var _frameH = 0
    private var _frameFormat: UInt32 = 0
    private var _frames = 0
    private var _obs = 0
    private var _hands = 0
    private var _err = "none"

    var device: String { lock.lock(); defer { lock.unlock() }; return _device }
    var frames: Int { lock.lock(); defer { lock.unlock() }; return _frames }
    var obs: Int { lock.lock(); defer { lock.unlock() }; return _obs }
    var hands: Int { lock.lock(); defer { lock.unlock() }; return _hands }
    var err: String { lock.lock(); defer { lock.unlock() }; return _err }

    var frame: String {
        lock.lock(); defer { lock.unlock() }
        guard _frameW > 0 else { return "—" }
        let fcc = _frameFormat
        let chars = [(fcc >> 24) & 0xFF, (fcc >> 16) & 0xFF, (fcc >> 8) & 0xFF, fcc & 0xFF]
            .map { Character(UnicodeScalar(UInt8($0))) }
        return "\(_frameW)×\(_frameH) \(String(chars))"
    }

    func setDevice(_ s: String) { lock.lock(); _device = s; lock.unlock() }
    func noteFrame(width: Int, height: Int, pixelFormat: UInt32) {
        lock.lock()
        _frames += 1
        _frameW = width
        _frameH = height
        _frameFormat = pixelFormat
        lock.unlock()
    }
    func noteDetection(obs: Int, hands: Int, err: String) {
        lock.lock()
        _obs = obs
        _hands = hands
        _err = err
        lock.unlock()
    }
}