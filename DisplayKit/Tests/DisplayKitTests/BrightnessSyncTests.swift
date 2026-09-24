import Testing
@testable import DisplayKit

struct BrightnessSyncTests {
    private let laptop: UInt32 = 1
    private let monitor: UInt32 = 2

    private func synced(laptop laptopValue: Double, monitor monitorValue: Double) -> BrightnessSync {
        var sync = BrightnessSync()
        sync.rebase(to: [laptop: laptopValue, monitor: monitorValue])
        return sync
    }

    private func expect(_ value: Double?, equals expected: Double) {
        #expect(abs((value ?? -1) - expected) < 1e-9)
    }

    @Test func followersMoveByTheSameAmountKeepingTheirOffset() {
        var sync = synced(laptop: 0.5, monitor: 0.7)
        expect(sync.change(laptop, from: 0.5, to: 0.6)[monitor], equals: 0.8)
        expect(sync.change(monitor, from: 0.8, to: 0.4)[laptop], equals: 0.2)
    }

    @Test func changedDisplayIsNotToldToMove() {
        var sync = synced(laptop: 0.5, monitor: 0.7)
        #expect(sync.change(laptop, from: 0.5, to: 0.6)[laptop] == nil)
    }

    @Test func offsetSurvivesAFollowerHittingTheLimit() {
        var sync = synced(laptop: 0.5, monitor: 0.9)
        // The monitor pins at 100% while the laptop keeps rising...
        expect(sync.change(laptop, from: 0.5, to: 0.8)[monitor], equals: 1.0)
        // ...and returns to its original +0.4 offset on the way back down.
        expect(sync.change(laptop, from: 0.8, to: 0.5)[monitor], equals: 0.9)
    }

    @Test func movingAPinnedDisplayDirectlyDoesNotMakeOthersJump() {
        var sync = synced(laptop: 0.5, monitor: 0.9)
        _ = sync.change(laptop, from: 0.5, to: 0.8)  // monitor pinned at 1.0, wants 1.2
        // Nudging the pinned monitor down by 0.1 moves the laptop by 0.1, not by the hidden 0.3.
        expect(sync.change(monitor, from: 1.0, to: 0.9)[laptop], equals: 0.7)
    }

    @Test func unknownDisplayIsIgnored() {
        var sync = synced(laptop: 0.5, monitor: 0.7)
        #expect(sync.change(99, from: 0.1, to: 0.9).isEmpty)
    }

    @Test func rebaseAdoptsNewDifferences() {
        var sync = synced(laptop: 0.5, monitor: 0.7)
        sync.rebase(to: [laptop: 0.5, monitor: 0.5])
        expect(sync.change(laptop, from: 0.5, to: 0.3)[monitor], equals: 0.3)
    }

    @Test func alignedDisplaysMoveInLockstep() {
        var sync = BrightnessSync()
        sync.align([laptop, monitor], to: 0.5)
        expect(sync.change(laptop, from: 0.5, to: 0.0)[monitor], equals: 0.0)
        expect(sync.change(monitor, from: 0.0, to: 0.17)[laptop], equals: 0.17)
    }

    @Test func alignedDisplaysStayTogetherAtTheLimits() {
        var sync = BrightnessSync()
        sync.align([laptop, monitor], to: 0.9)
        expect(sync.change(laptop, from: 0.9, to: 1.0)[monitor], equals: 1.0)
        expect(sync.change(laptop, from: 1.0, to: 0.4)[monitor], equals: 0.4)
    }
}
