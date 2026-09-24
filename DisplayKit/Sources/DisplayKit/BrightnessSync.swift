import CoreGraphics
import Foundation

/// The arithmetic behind brightness sync. The displays share one `level`, and each shows it through
/// its own curve, `level ^ exponent`. Every curve runs from 0% to 100%, so the displays keep the
/// relationship they had when sync started in between, yet reach 0% and 100% together.
public struct BrightnessSync {
    private var level = 0.0
    private var exponents: [CGDirectDisplayID: Double] = [:]

    /// Keeps a curve from getting so steep that a display jumps between near-off and near-full.
    private static let exponentRange = 0.2...5.0

    public init() {}

    /// Starts over from the displays' current brightness: `leader`'s becomes the shared level and
    /// every other display keeps its current relationship to it.
    public mutating func rebase(to values: [CGDirectDisplayID: Double], leader: CGDirectDisplayID) {
        level = values[leader] ?? 0
        exponents = [:]
        add(values)
    }

    /// Follows a change in which displays are connected: displays already synced keep their curves,
    /// new ones are fitted to their current brightness, and missing ones are dropped.
    public mutating func update(to values: [CGDirectDisplayID: Double], leader: CGDirectDisplayID) {
        exponents = exponents.filter { values[$0.key] != nil }
        guard !exponents.isEmpty else { return rebase(to: values, leader: leader) }
        add(values.filter { exponents[$0.key] == nil })
    }

    /// Records a brightness change on one display and returns the brightness every other display should move to.
    public mutating func change(_ display: CGDirectDisplayID, to new: Double) -> [CGDirectDisplayID: Double] {
        guard let exponent = exponents[display] else { return [:] }
        level = pow(min(1, max(0, new)), 1 / exponent)
        return exponents.filter { $0.key != display }.mapValues { pow(level, $0) }
    }

    private mutating func add(_ values: [CGDirectDisplayID: Double]) {
        for (display, value) in values { exponents[display] = Self.exponent(from: level, to: value) }
    }

    /// The curve through (level, value). Without a level strictly between 0 and 1 there is no
    /// relationship to keep, so the display simply matches the level.
    private static func exponent(from level: Double, to value: Double) -> Double {
        guard level > 0, level < 1, value > 0, value < 1 else { return 1 }
        return min(exponentRange.upperBound, max(exponentRange.lowerBound, log(value) / log(level)))
    }
}
