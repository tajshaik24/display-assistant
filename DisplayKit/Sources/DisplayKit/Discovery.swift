import AppKit
import CIOAVService
import CoreGraphics
import IOKit

/// An external display that has a DDC channel.
public struct ExternalDisplay {
    public let id: CGDirectDisplayID
    public let name: String
    public let ddc: DDCChannel
}

public enum DisplayDiscovery {
    /// EDID identity of the display attached to an external AV service.
    private struct ServiceIdentity {
        var vendor: UInt32?
        var product: UInt32?
        var serial: UInt32?
        var name: String?
    }

    /// Apple's own displays are controlled natively by macOS and don't speak DDC, so leave them alone.
    private static let appleVendorID: UInt32 = 0x610

    public static func externalDisplays() -> [ExternalDisplay] {
        var services = externalAVServices().filter { $0.identity.vendor != appleVendorID }
        var result: [ExternalDisplay] = []

        for id in onlineExternalDisplayIDs() {
            guard !services.isEmpty else { break }
            // Prefer an exact EDID match; with a single candidate left, order is good enough.
            let index = services.firstIndex { matches($0.identity, display: id) } ?? 0
            let (service, identity) = services.remove(at: index)
            let name = screenName(for: id) ?? identity.name ?? "External Display"
            result.append(ExternalDisplay(id: id, name: name, ddc: DDCChannel(service: service)))
        }
        return result
    }

    private static func onlineExternalDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayVendorNumber($0) != appleVendorID }
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

    /// The EDID attributes live on the IOMobileFramebufferShim that shares a
    /// `dispext` ancestor with the AV service, so walk up until we find one.
    private static func identity(forAVService entry: io_registry_entry_t) -> ServiceIdentity {
        var current = entry
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        while true {
            if let attributes = childDisplayAttributes(of: current) {
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
