import Foundation

/// Serializes DDC traffic for one display and coalesces writes, so dragging a
/// slider only ever sends the most recent value instead of queueing every step.
public final class DDCWriter: @unchecked Sendable {
    private let ddc: DDCChannel
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: [VCPCode: UInt16] = [:]
    private var isDraining = false

    public init(ddc: DDCChannel, label: String) {
        self.ddc = ddc
        self.queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    public func set(_ code: VCPCode, to value: UInt16) {
        lock.lock()
        pending[code] = value
        let shouldStart = !isDraining
        isDraining = true
        lock.unlock()

        if shouldStart { queue.async { self.drain() } }
    }

    /// Reads several codes in one go, off the main thread. Missing keys mean the display did not answer.
    public func read(_ codes: [VCPCode], completion: @escaping @Sendable ([VCPCode: VCPValue]) -> Void) {
        queue.async {
            var values: [VCPCode: VCPValue] = [:]
            for code in codes { values[code] = self.ddc.read(code) }
            completion(values)
        }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let (code, value) = pending.first else {
                isDraining = false
                lock.unlock()
                return
            }
            pending[code] = nil
            lock.unlock()

            ddc.write(code, value: value)
        }
    }
}
