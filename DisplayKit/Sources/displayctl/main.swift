import DisplayKit
import Foundation

let usage = """
usage: displayctl list
       displayctl get <brightness|volume|mute> [display-index]
       displayctl set <brightness|volume|mute> <value> [display-index]
       displayctl hdr <on|off|status> [display-index]

Values are 0-100 (mute: 1 = muted, 2 = unmuted). Natively controlled displays take brightness from macOS; volume and mute always go over DDC.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let codes: [String: VCPCode] = ["brightness": .brightness, "volume": .volume, "mute": .mute]
let args = Array(CommandLine.arguments.dropFirst())
let displays = DisplayDiscovery.displays()

func display(at argIndex: Int) -> ControllableDisplay {
    let index = args.count > argIndex ? Int(args[argIndex]) ?? -1 : 0
    guard displays.indices.contains(index) else { fail("no controllable display at index \(index)") }
    return displays[index]
}

/// Current and maximum value, on the display's own scale (native brightness is reported as 0-100).
func read(_ code: VCPCode, from display: ControllableDisplay) -> (current: Int, max: Int)? {
    if code == .brightness, display.hasNativeBrightness {
        return NativeBrightness.get(display.id).map { (Int(($0 * 100).rounded()), 100) }
    }
    return display.ddc?.read(code).map { (Int($0.current), Int($0.max)) }
}

func write(_ code: VCPCode, value: UInt16, to display: ControllableDisplay) -> Bool {
    if code == .brightness, display.hasNativeBrightness {
        return NativeBrightness.set(display.id, to: Double(value) / 100)
    }
    return display.ddc?.write(code, value: value) ?? false
}

switch args.first {
case "list":
    if displays.isEmpty { print("no controllable displays found") }
    for (index, display) in displays.enumerated() {
        let kind = [display.hasNativeBrightness ? "native" : nil, display.ddc != nil ? "DDC" : nil].compactMap { $0 }.joined(separator: " + ")
        let values = [("brightness", VCPCode.brightness), ("volume", .volume), ("mute", .mute)]
            .compactMap { name, code in read(code, from: display).map { "\(name)=\($0.current)/\($0.max)" } }
            .joined(separator: " ")
        print("[\(index)] \(display.name) (id \(display.id), \(kind)): \(values.isEmpty ? "not answering" : values)")
    }
case "get":
    guard args.count >= 2, let code = codes[args[1]] else { fail(usage) }
    guard let value = read(code, from: display(at: 2)) else { fail("display did not answer") }
    print("\(value.current)/\(value.max)")
case "set":
    guard args.count >= 3, let code = codes[args[1]], let value = UInt16(args[2]) else { fail(usage) }
    guard write(code, value: value, to: display(at: 3)) else { fail("write failed") }
case "hdr":
    guard args.count >= 2, ["on", "off", "status"].contains(args[1]) else { fail(usage) }
    let id = display(at: 2).id
    guard HDRMode.isSupported(id) else { fail("display does not support HDR") }
    if args[1] != "status", !HDRMode.setEnabled(id, args[1] == "on") { fail("could not switch HDR") }
    if args[1] == "status" { print(HDRMode.isEnabled(id) ? "on" : "off") }
default:
    fail(usage)
}
