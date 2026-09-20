import DisplayKit
import Foundation

let usage = """
usage: displayctl list
       displayctl get <brightness|volume|mute> [display-index]
       displayctl set <brightness|volume|mute> <value> [display-index]

Values are 0-100 (mute: 1 = muted, 2 = unmuted). Natively controlled displays only have brightness.
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
    switch display.backend {
    case .ddc(let channel):
        return channel.read(code).map { (Int($0.current), Int($0.max)) }
    case .native:
        guard code == .brightness, let brightness = NativeBrightness.get(display.id) else { return nil }
        return (Int((brightness * 100).rounded()), 100)
    }
}

func write(_ code: VCPCode, value: UInt16, to display: ControllableDisplay) -> Bool {
    switch display.backend {
    case .ddc(let channel): channel.write(code, value: value)
    case .native: code == .brightness && NativeBrightness.set(display.id, to: Double(value) / 100)
    }
}

switch args.first {
case "list":
    if displays.isEmpty { print("no controllable displays found") }
    for (index, display) in displays.enumerated() {
        let kind = if case .native = display.backend { "native" } else { "DDC" }
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
default:
    fail(usage)
}
