import DisplayKit
import Foundation

let usage = """
usage: displayctl list
       displayctl get <brightness|volume|mute> [display-index]
       displayctl set <brightness|volume|mute> <value> [display-index]
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let codes: [String: VCPCode] = ["brightness": .brightness, "volume": .volume, "mute": .mute]
let args = Array(CommandLine.arguments.dropFirst())
let displays = DisplayDiscovery.externalDisplays()

func display(at argIndex: Int) -> ExternalDisplay {
    let index = args.count > argIndex ? Int(args[argIndex]) ?? -1 : 0
    guard displays.indices.contains(index) else { fail("no external display at index \(index)") }
    return displays[index]
}

switch args.first {
case "list":
    if displays.isEmpty { print("no DDC-capable external displays found") }
    for (index, display) in displays.enumerated() {
        let values = [("brightness", VCPCode.brightness), ("volume", .volume), ("mute", .mute)]
            .map { name, code in "\(name)=\(display.ddc.read(code).map { "\($0.current)/\($0.max)" } ?? "n/a")" }
            .joined(separator: " ")
        print("[\(index)] \(display.name) (id \(display.id)): \(values)")
    }
case "get":
    guard args.count >= 2, let code = codes[args[1]] else { fail(usage) }
    guard let value = display(at: 2).ddc.read(code) else { fail("display did not answer") }
    print("\(value.current)/\(value.max)")
case "set":
    guard args.count >= 3, let code = codes[args[1]], let value = UInt16(args[2]) else { fail(usage) }
    guard display(at: 3).ddc.write(code, value: value) else { fail("write failed") }
default:
    fail(usage)
}
