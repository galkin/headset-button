import Testing

@testable import HeadsetButtonCore

@Suite struct GestureTests {
    @Test func commandsMapToGestures() {
        #expect(Gesture(command: .play) == .single)
        #expect(Gesture(command: .pause) == .single)
        #expect(Gesture(command: .togglePlayPause) == .single)
        #expect(Gesture(command: .nextTrack) == .double)
        #expect(Gesture(command: .previousTrack) == .triple)
    }

    @Test func everyGestureHasACommand() {
        let reached = Set(RemoteCommand.allCases.map(Gesture.init(command:)))
        #expect(reached == Set(Gesture.allCases))
    }
}
