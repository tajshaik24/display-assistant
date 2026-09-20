import CoreGraphics

/// The arithmetic behind brightness sync. Every display sits at `level + offset`, clamped to 0...1,
/// so the differences between displays survive one of them hitting 0% or 100% and coming back.
public struct BrightnessSync {
    private var level = 0.0
    private var offsets: [CGDirectDisplayID: Double] = [:]

    public init() {}

    /// Takes the displays' current differences as the ones to keep.
    public mutating func rebase(to values: [CGDirectDisplayID: Double]) {
        level = 0
        offsets = values
    }

    /// Records a brightness change on one display and returns the brightness every other display should move to.
    public mutating func change(_ display: CGDirectDisplayID, from old: Double, to new: Double) -> [CGDirectDisplayID: Double] {
        guard offsets[display] != nil else { return [:] }
        level += new - old
        // Unchanged unless this display had been pinned at 0% or 100%, in which case moving it
        // directly is the user choosing a new offset for it.
        offsets[display] = new - level
        return offsets.filter { $0.key != display }.mapValues { min(1, max(0, level + $0)) }
    }
}
