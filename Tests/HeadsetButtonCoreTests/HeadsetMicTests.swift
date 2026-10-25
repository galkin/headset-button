import Foundation
import Testing
@testable import HeadsetButtonCore

@Suite struct HeadsetInputDevicesTests {
    func device(_ id: UInt32, _ name: String, uid: String = "", _ transport: AudioDeviceSummary.Transport, input: Bool, output: Bool) -> AudioDeviceSummary {
        AudioDeviceSummary(id: id, name: name, uid: uid, modelUID: "", transport: transport, hasInput: input, hasOutput: output)
    }

    @Test func prefersAirPodsOverOtherBluetoothInputs() {
        let devices = [
            device(1, "MacBook Air Microphone", .other, input: true, output: false),
            device(2, "CouchVox Microphone", .bluetoothLE, input: true, output: false),
            device(3, "Jabra Evolve", .bluetooth, input: true, output: true),
            device(4, "Nikita’s AirPods Max", .bluetooth, input: true, output: true),
        ]
        #expect(HeadsetInputDevices.select(from: devices).map(\.id) == [4])
    }

    @Test func fallsBackToBluetoothHeadsetsWithOutput() {
        let devices = [
            device(2, "CouchVox Microphone", uid: "com.couchvox.AudioDevice", .bluetoothLE, input: true, output: false),
            device(3, "Headset", uid: "AA-BB-CC-DD-EE-FF:input", .bluetooth, input: true, output: false),
            device(5, "Headset", uid: "aa-bb-cc-dd-ee-ff:output", .bluetooth, input: false, output: true),
            device(6, "Built-in", .other, input: true, output: true),
        ]
        #expect(HeadsetInputDevices.select(from: devices).map(\.id) == [3])
    }

    @Test func noHeadsetConnected() {
        #expect(HeadsetInputDevices.select(from: [device(1, "Mic", .other, input: true, output: false)]).isEmpty)
    }
}

@Suite struct HeadsetMicRecordersTests {
    @Test func onlyOtherProcessesRecordingFromTheHeadset() {
        let processes = [
            AudioProcessSummary(pid: 10, bundleID: "us.zoom.xos", isRunningInput: true, inputDeviceIDs: [4]),
            AudioProcessSummary(pid: 11, bundleID: "com.example.builtin", isRunningInput: true, inputDeviceIDs: [1]),
            AudioProcessSummary(pid: 12, bundleID: "com.example.idle", isRunningInput: false, inputDeviceIDs: [4]),
            AudioProcessSummary(pid: 99, bundleID: "in.galk.HeadsetButton", isRunningInput: true, inputDeviceIDs: [4]),
        ]
        let recording = HeadsetMicRecorders.recording(processes: processes, headsetDeviceIDs: [4], ownPID: 99)
        #expect(recording.map(\.pid) == [10])
    }
}

@Suite struct MicBusyNotificationRuleTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func busySoonAfterAnActionNotifiesOnce() {
        var rule = MicBusyNotificationRule()
        rule.actionRan(at: t0)
        do { let posted = rule.micBusyChanged(true, at: t0.addingTimeInterval(0.4)); #expect(posted) }
        do { let posted = rule.micBusyChanged(true, at: t0.addingTimeInterval(0.5)); #expect(!posted) }
        do { let posted = rule.micBusyChanged(false, at: t0.addingTimeInterval(2)); #expect(!posted) }
        do { let posted = rule.micBusyChanged(true, at: t0.addingTimeInterval(2.1)); #expect(!posted) }
    }

    @Test func busyLongAfterAnActionOrWithoutOneIsSilent() {
        var rule = MicBusyNotificationRule()
        do { let posted = rule.micBusyChanged(true, at: t0); #expect(!posted) }
        do { let posted = rule.micBusyChanged(false, at: t0.addingTimeInterval(1)); #expect(!posted) }
        rule.actionRan(at: t0.addingTimeInterval(2))
        do { let posted = rule.micBusyChanged(true, at: t0.addingTimeInterval(2 + MicBusyNotificationRule.window + 0.1)); #expect(!posted) }
    }

    @Test func windowBoundaryAndAlreadyBusy() {
        var rule = MicBusyNotificationRule()
        rule.actionRan(at: t0)
        do { let posted = rule.micBusyChanged(true, at: t0.addingTimeInterval(MicBusyNotificationRule.window)); #expect(posted) }

        var already = MicBusyNotificationRule()
        _ = already.micBusyChanged(true, at: t0)
        already.actionRan(at: t0.addingTimeInterval(1))
        do { let posted = already.micBusyChanged(true, at: t0.addingTimeInterval(1.2)); #expect(!posted) }
    }

    @Test func body() {
        #expect(MicBusyNotificationRule.body(for: HeadsetMicBusy(appName: "superwhisper", headsetName: "Nikita’s AirPods Max"))
            == "superwhisper records from Nikita’s AirPods Max — stop it from the keyboard")
    }
}

@Suite struct LastPressTextTests {
    @Test func formats() {
        #expect(LastPressText.text(gesture: .single, elapsed: 3.7) == "Last press: Single, 3 s ago")
        #expect(LastPressText.text(gesture: .double, elapsed: 0.2) == "Last press: Double, just now")
        #expect(LastPressText.text(gesture: .triple, elapsed: 59.9) == "Last press: Triple, 59 s ago")
        #expect(LastPressText.text(gesture: .single, elapsed: 125) == "Last press: Single, 2 min ago")
        #expect(LastPressText.text(gesture: .single, elapsed: 7200) == "Last press: Single, 2 h ago")
        #expect(LastPressText.text(gesture: .single, elapsed: -1) == "Last press: Single, just now")
    }
}
