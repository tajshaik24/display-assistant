import Testing
@testable import DisplayKit

struct BrightnessSyncTests {
    private let laptop: UInt32 = 1
    private let monitor: UInt32 = 2

    private func synced(laptop laptopValue: Double, monitor monitorValue: Double) -> BrightnessSync {
        var sync = BrightnessSync()
        sync.rebase(to: [laptop: laptopValue, monitor: monitorValue], leader: laptop)
        return sync
    }

    private func expect(_ value: Double?, equals expected: Double) {
        #expect(abs((value ?? -1) - expected) < 1e-9)
    }

    @Test func displaysReachZeroTogether() {
        var sync = synced(laptop: 0.5, monitor: 0.67)
        expect(sync.change(laptop, to: 0)[monitor], equals: 0)
        expect(sync.change(monitor, to: 0)[laptop], equals: 0)
    }

    @Test func displaysReachFullTogether() {
        var sync = synced(laptop: 0.5, monitor: 0.67)
        expect(sync.change(laptop, to: 1)[monitor], equals: 1)
    }

    @Test func relationshipSurvivesAGoingToZeroAndBack() {
        var sync = synced(laptop: 0.5, monitor: 0.67)
        _ = sync.change(laptop, to: 0)
        expect(sync.change(laptop, to: 0.5)[monitor], equals: 0.67)
    }

    @Test func followerKeepsItsSideOfTheLeader() {
        var sync = synced(laptop: 0.5, monitor: 0.67)
        let monitorValue = sync.change(laptop, to: 0.25)[monitor] ?? 0
        #expect(monitorValue > 0.25 && monitorValue < 0.67)
    }

    @Test func movingTheFollowerMovesTheLeaderAlongTheSameCurve() {
        var sync = synced(laptop: 0.5, monitor: 0.67)
        expect(sync.change(monitor, to: 0.67)[laptop], equals: 0.5)
    }

    @Test func equalDisplaysStayEqual() {
        var sync = synced(laptop: 0.4, monitor: 0.4)
        expect(sync.change(laptop, to: 0.9)[monitor], equals: 0.9)
        expect(sync.change(monitor, to: 0.1)[laptop], equals: 0.1)
    }

    @Test func leaderAtAnEndMeansDisplaysMatch() {
        var sync = synced(laptop: 0, monitor: 0.17)
        expect(sync.change(laptop, to: 0.3)[monitor], equals: 0.3)
    }

    @Test func changedDisplayIsNotToldToMove() {
        var sync = synced(laptop: 0.5, monitor: 0.7)
        #expect(sync.change(laptop, to: 0.6)[laptop] == nil)
    }

    @Test func unknownDisplayIsIgnored() {
        var sync = synced(laptop: 0.5, monitor: 0.7)
        #expect(sync.change(99, to: 0.9).isEmpty)
    }

    @Test func updateKeepsExistingCurvesAndFitsNewDisplays() {
        var sync = synced(laptop: 0.5, monitor: 0.67)
        let other: UInt32 = 3
        sync.update(to: [laptop: 0.5, monitor: 0.67, other: 0.25], leader: laptop)
        let targets = sync.change(laptop, to: 0)
        expect(targets[monitor], equals: 0)
        expect(targets[other], equals: 0)
        expect(sync.change(laptop, to: 0.5)[other], equals: 0.25)
    }

    @Test func updateWithNothingSyncedStartsOver() {
        var sync = BrightnessSync()
        sync.update(to: [laptop: 0.5], leader: laptop)
        sync.update(to: [laptop: 0.5, monitor: 0.67], leader: laptop)
        expect(sync.change(laptop, to: 0)[monitor], equals: 0)
        expect(sync.change(laptop, to: 0.5)[monitor], equals: 0.67)
    }
}
