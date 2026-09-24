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

    public static func displays() -> [ControllableDisplay] {
        var services = externalAVServices().filter { $0.identity.vendor != appleVendorID }
        var result: [ControllableDisplay] = []

        for id in onlineDisplayIDs() {
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            // With HDR on, macOS takes over a third-party monitor's brightness too, but its speakers still need DDC.
            let isNative = NativeBrightness.canChange(id)
            var identity: ServiceIdentity?
            var ddc: DDCChannel?
            if !isBuiltIn, CGDisplayVendorNumber(id) != appleVendorID, !services.isEmpty {
                // Prefer an exact EDID match; with a single candidate left, order is good enough. A native display
                // (an LG UltraFine, say) may not speak DDC at all, so it only takes an exact match.
                if let index = services.firstIndex(where: { matches($0.identity, display: id) }) ?? (isNative ? nil : 0) {
                    let entry = services.remove(at: index)
                    identity = entry.identity
                    ddc = DDCChannel(service: entry.service)
                }
            }
            guard isNative || ddc != nil else { continue }
            let name = screenName(for: id) ?? identity?.name ?? (isBuiltIn ? "Built-in Display" : "External Display")
            result.append(ControllableDisplay(id: id, name: name, isBuiltIn: isBuiltIn, hasNativeBrightness: isNative, ddc: ddc))
        }
        return result
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    private static func screenName(for id: CGDirectDisplayID) -> String? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }?.localizedName
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
