import CoreAudio

/// Answers whether sound is currently going to a display, which macOS cannot adjust itself.
enum AudioOutput {
    /// Name of the default output device when it is a display (DisplayPort/HDMI/USB-C video), else nil.
    static var displayDeviceName: String? {
        guard let device = defaultOutputDevice else { return nil }
        var transport: UInt32 = 0
        guard read(device, kAudioDevicePropertyTransportType, into: &transport),
              transport == kAudioDeviceTransportTypeDisplayPort || transport == kAudioDeviceTransportTypeHDMI
        else { return nil }

        var name: Unmanaged<CFString>?
        guard read(device, kAudioObjectPropertyName, into: &name), let name else { return "" }
        return name.takeRetainedValue() as String
    }

    private static var defaultOutputDevice: AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        guard read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, into: &device),
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) == noErr
        }
    }
}
