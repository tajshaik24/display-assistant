import AppKit
import CIOAVService
import CoreGraphics
import IOKit

/// A display that can be controlled natively, over DDC/CI, or both.
public struct ControllableDisplay {
    public let id: CGDirectDisplayID
    public let name: String
    public let isBuiltIn: Bool
    /// True when macOS controls the brightness itself, through ``NativeBrightness``: built-in panels,
    /// Apple displays, and third-party monitors while HDR is on.
    public let hasNativeBrightness: Bool
    /// The DDC/CI channel of a third-party monitor: brightness (unless native), volume and mute.
    public let ddc: DDCChannel?
}

public enum DisplayDiscovery {
    /// EDID identity of the display attached to an external AV service.
    private struct ServiceIdentity {
        var vendor: UInt32?
        var product: UInt32?
        var serial: UInt32?
        var name: String?
    }

    /// Apple's own displays don't speak DDC; they are only ever controlled natively.
    private static let appleVendorID: UInt32 = 0x610

    /// Makes DisplayServices calls, which can stall, so an app should call it off the main thread, passing
    /// `names` read from ``screenNames()`` on the main thread first.
    public static func displays(names: [CGDirectDisplayID: String] = screenNames()) -> [ControllableDisplay] {
        var services = externalAVServices().filter { $0.identity.vendor != appleVendorID }
        let ids = onlineDisplayIDs()
        // With HDR on, macOS takes over a third-party monitor's brightness too, but its speakers still need DDC.
        let native = Dictionary(uniqueKeysWithValues: ids.map { ($0, NativeBrightness.canChange($0)) })
        let candidates = ids.filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayVendorNumber($0) != appleVendorID }

        // Exact EDID matches first, so a monitor without one can't take another's service. Leftovers then go
        // in order, which is right whenever a single one is left. A native display (an LG UltraFine, say) may
        // not speak DDC at all, so it only takes an exact match.
        var assigned: [CGDirectDisplayID: (service: IOAVService, identity: ServiceIdentity)] = [:]
        for id in candidates {
            if let index = services.firstIndex(where: { matches($0.identity, display: id) }) {
                assigned[id] = services.remove(at: index)
            }
        }
        for id in candidates where assigned[id] == nil && native[id] == false && !services.isEmpty {
            assigned[id] = services.removeFirst()
        }

        return ids.compactMap { id in
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let isNative = native[id] ?? false
            let entry = assigned[id]
            guard isNative || entry != nil else { return nil }
            let name = names[id] ?? entry?.identity.name ?? (isBuiltIn ? "Built-in Display" : "External Display")
            return ControllableDisplay(
                id: id, name: name, isBuiltIn: isBuiltIn, hasNativeBrightness: isNative,
                ddc: entry.map { DDCChannel(service: $0.service) }
            )
        }
    }

    /// Calls `handler` on the main queue whenever an external AV service appears. A monitor that re-links
    /// (after it wakes, say) gets a new service without macOS reconfiguring the screen, and DDC channels
    /// opened on the old one then fail silently. Keep the returned observer alive to keep watching.
    public static func observeAVServices(_ handler: @escaping () -> Void) -> AnyObject? {
        AVServiceObserver(handler: handler)
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    /// The name each display's screen shows in System Settings. AppKit, so read it on the main thread.
    public static func screenNames() -> [CGDirectDisplayID: String] {
        Dictionary(NSScreen.screens.compactMap { screen in screen.displayID.map { ($0, screen.localizedName) } }) { first, _ in first }
    }

    private static func matches(_ identity: ServiceIdentity, display id: CGDirectDisplayID) -> Bool {
        guard let vendor = identity.vendor, let product = identity.product else { return false }
        guard vendor == CGDisplayVendorNumber(id), product == CGDisplayModelNumber(id) else { return false }
        let serial = CGDisplaySerialNumber(id)
        return serial == 0 || identity.serial == nil || identity.serial == serial
    }

    private static func externalAVServices() -> [(service: IOAVService, identity: ServiceIdentity)] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var result: [(IOAVService, ServiceIdentity)] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard property(entry, "Location") as? String == "External",
                  let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) else { continue }
            result.append((service, identity(forAVService: entry)))
        }
        return result
    }

    /// The EDID attributes live on an IOMobileFramebufferShim near the AV service: either under a shared
    /// ancestor, or (on newer chips) under the `dispextN` node that sits beside the service's `dcpextN`.
    private static func identity(forAVService entry: io_registry_entry_t) -> ServiceIdentity {
        var current = entry
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        while true {
            if let attributes = childDisplayAttributes(of: current) ?? counterpartDisplayAttributes(of: current) {
                let product = attributes["ProductAttributes"] as? [String: Any] ?? [:]
                return ServiceIdentity(
                    vendor: (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value,
                    product: (product["ProductID"] as? NSNumber)?.uint32Value,
                    serial: (product["SerialNumber"] as? NSNumber)?.uint32Value,
                    name: product["ProductName"] as? String
                )
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            IOObjectRelease(current)
            current = parent
        }
        return ServiceIdentity()
    }

    /// For a `dcpextN` node, the display attributes under its `dispextN` sibling.
    private static func counterpartDisplayAttributes(of entry: io_registry_entry_t) -> [String: Any]? {
        var nameBuffer = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &nameBuffer) == KERN_SUCCESS else { return nil }
        let name = String(cString: nameBuffer)
        guard name.hasPrefix("dcpext") else { return nil }
        let counterpart = "disp" + name.dropFirst("dcp".count)

        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(parent) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(parent, kIOServicePlane, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let sibling = IOIteratorNext(iterator), sibling != 0 {
            defer { IOObjectRelease(sibling) }
            guard IORegistryEntryGetName(sibling, &nameBuffer) == KERN_SUCCESS, String(cString: nameBuffer) == counterpart else { continue }
            return childDisplayAttributes(of: sibling)
        }
        return nil
    }

    private static func childDisplayAttributes(of entry: io_registry_entry_t) -> [String: Any]? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            if let attributes = property(child, "DisplayAttributes") as? [String: Any] { return attributes }
        }
        return nil
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

private final class AVServiceObserver {
    private let handler: () -> Void
    private let port: IONotificationPortRef
    private var iterator: io_iterator_t = 0

    init?(handler: @escaping () -> Void) {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return nil }
        self.handler = handler
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let observer = Unmanaged<AVServiceObserver>.fromOpaque(refcon).takeUnretainedValue()
            if observer.drain(iterator) { observer.handler() }
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("DCPAVServiceProxy"),
                                               callback, refcon, &iterator) == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            return nil
        }
        // The notification is only armed once the services already present have been drained.
        drain(iterator)
    }

    deinit {
        IOObjectRelease(iterator)
        IONotificationPortDestroy(port)
    }

    /// Releases every service in `iterator`; true if there was any.
    @discardableResult
    private func drain(_ iterator: io_iterator_t) -> Bool {
        var found = false
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            IOObjectRelease(entry)
            found = true
        }
        return found
    }
}

extension NSScreen {
    /// The Core Graphics display this screen shows.
    public var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
