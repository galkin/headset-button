import Testing
@testable import HeadsetButtonCore

@Suite struct SourceFilterTests {
    @Test func bluetoothdIsAGesture() {
        #expect(SourceFilter.decide(sourceID: "com.apple.bluetoothd") == .accepted)
        #expect(SourceFilter.decide(sourceID: "com.apple.bluetoothd:AA-BB") == .accepted)
    }

    @Test func otherSendersAreDropped() {
        #expect(SourceFilter.decide(sourceID: "com.apple.rcd") == .dropped)
        #expect(SourceFilter.decide(sourceID: "com.apple.controlcenter") == .dropped)
        #expect(!SourceFilter.decide(sourceID: "com.apple.rcd").accepts)
    }

    @Test func unreadableSourceBypassesTheFilter() {
        #expect(SourceFilter.decide(sourceID: nil) == .acceptedUnfiltered)
        #expect(SourceFilter.decide(sourceID: "") == .acceptedUnfiltered)
        #expect(SourceFilter.decide(sourceID: nil).accepts)
    }
}
