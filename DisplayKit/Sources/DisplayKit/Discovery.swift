import AppKit
import CIOAVService
import CoreGraphics
import IOKit

/// A display whose brightness can be controlled, one way or the other.
public struct ControllableDisplay {
    public enum Backend {
        /// A third-party monitor, controlled over DDC/CI (brightness, volume, mute).
        case ddc(DDCChannel)
        /// A display macOS controls itself; brightness only, through ``NativeBrightness``.
        case native
    }

    public let id: CGDirectDisplayID
    public let name: String
    public let isBuiltIn: Bool
    public let backend: Backend
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
            if NativeBrightness.canChange(id) {
                let name = screenName(for: id) ?? (isBuiltIn ? "Built-in Display" : "Display")
                result.append(ControllableDisplay(id: id, name: name, isBuiltIn: isBuiltIn, backend: .native))
                continue
            }
            guard !isBuiltIn, CGDisplayVendorNumber(id) != appleVendorID, !services.isEmpty else { continue }
            // Prefer an exact EDID match; with a single candidate left, order is good enough.
            let index = services.firstIndex { matches($0.identity, display: id) } ?? 0
            let (service, identity) = services.remove(at: index)
            let name = screenName(for: id) ?? identity.name ?? "External Display"
            result.append(ControllableDisplay(id: id, name: name, isBuiltIn: false, backend: .ddc(DDCChannel(service: service))))
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
