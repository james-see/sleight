import Foundation
import CoreMIDI
import Combine

/// Monitors whether a MIDI host (DAW) is connected by polling the system
/// destination count. When a host is open and has enumerated Sleight's
/// virtual source, destinations are > 0.
final class MIDIHostWatcher: ObservableObject {
    @Published var hostConnected = false

    private var timer: Timer?

    /// Pure function for testability - the logic is just "> 0" but isolating
    /// it makes the threshold testable without a live CoreMIDI setup.
    static func computeHostConnected(destinationCount: Int) -> Bool {
        destinationCount > 0
    }

    func startMonitoring(interval: TimeInterval = 2.0) {
        timer?.invalidate()
        checkNow()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkNow()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkNow() {
        let count = MIDIGetNumberOfDestinations()
        let connected = Self.computeHostConnected(destinationCount: Int(count))
        if connected != hostConnected {
            DispatchQueue.main.async { [weak self] in
                self?.hostConnected = connected
            }
        }
    }
}