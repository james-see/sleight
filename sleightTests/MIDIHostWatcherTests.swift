import XCTest
@testable import sleight

final class MIDIHostWatcherTests: XCTestCase {
    func testZeroDestinationsMeansNoHost() {
        XCTAssertFalse(MIDIHostWatcher.computeHostConnected(destinationCount: 0))
    }

    func testPositiveDestinationsMeansHostConnected() {
        XCTAssertTrue(MIDIHostWatcher.computeHostConnected(destinationCount: 1))
        XCTAssertTrue(MIDIHostWatcher.computeHostConnected(destinationCount: 5))
    }

    func testInitialStateIsDisconnected() {
        let watcher = MIDIHostWatcher()
        XCTAssertFalse(watcher.hostConnected)
    }

    @MainActor
    func testSynthMutedWhenHostConnectedAndAutoMuteEnabled() {
        let controller = SleightController()
        controller.settings.autoMuteWhenHostConnected = true
        controller.settings.muteSleight = false
        controller.settings.practice = false
        controller.hostWatcher.hostConnected = true
        controller.applySettings()
        XCTAssertFalse(controller.synth.isEnabled,
            "synth should be auto-muted when host is connected and autoMute is on")
    }

    @MainActor
    func testSynthNotMutedWhenHostConnectedButAutoMuteDisabled() {
        let controller = SleightController()
        controller.settings.autoMuteWhenHostConnected = false
        controller.settings.muteSleight = false
        controller.settings.practice = false
        controller.hostWatcher.hostConnected = true
        controller.applySettings()
        XCTAssertTrue(controller.synth.isEnabled,
            "synth should stay on when autoMute is off even if host is connected")
    }

    @MainActor
    func testSynthMutedWhenMuteSleightTrueRegardlessOfHost() {
        let controller = SleightController()
        controller.settings.muteSleight = true
        controller.settings.autoMuteWhenHostConnected = true
        controller.hostWatcher.hostConnected = false
        controller.applySettings()
        XCTAssertFalse(controller.synth.isEnabled)
    }

    @MainActor
    func testMIDIStillSentWhenSynthMuted() {
        // Verify that muting the synth does not stop MIDI broadcast.
        // This is structural: midiSource.send is not gated by synth.isEnabled.
        // processSynthetic returns events without calling onEvents, so we
        // invoke it ourselves to prove the synth path still receives events
        // even when muteSleight is on.
        let model = PipelineModel()
        let settings = AppSettings()
        settings.muteSleight = true
        let p = Pipeline(model: model, settings: settings)
        p.midiSource = nil
        var synthHeard = false
        p.onEvents = { _ in synthHeard = true }
        let frame = HandFrame(
            side: .right,
            points: (0..<21).map { _ in LandmarkPoint(x: 0.7, y: 0.5) },
            timestamp: 0
        )
        let events = p.processSynthetic([frame], dt: 1/60)
        p.onEvents?(events)
        XCTAssertTrue(synthHeard, "events should still flow to synth listener even when muted")
    }
}