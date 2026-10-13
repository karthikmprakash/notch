import AppKit
import CoreAudio
import SwiftUI

// MARK: - Wi-Fi

enum WiFi {
    /// The Wi-Fi device is not always en0; ask the hardware port list.
    static var device: String {
        if let output = shell("/usr/sbin/networksetup", ["-listallhardwareports"]) {
            let lines = output.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.contains("Wi-Fi") {
                if index + 1 < lines.count, lines[index + 1].hasPrefix("Device:") {
                    return lines[index + 1].replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return "en0"
    }

    static func isOn() -> Bool? {
        guard let output = shell("/usr/sbin/networksetup", ["-getairportpower", device]) else { return nil }
        if output.lowercased().contains(": on") { return true }
        if output.lowercased().contains(": off") { return false }
        return nil
    }

    /// Returns nil on success, or a message explaining what went wrong.
    static func set(_ on: Bool) -> String? {
        let argument = on ? "on" : "off"
        if let output = shell("/usr/sbin/networksetup", ["-setairportpower", device, argument]) {
            if output.isEmpty || !output.lowercased().contains("error") { return nil }
        }
        // networksetup needs an administrator for some setups: ask for it once.
        let script = "do shell script \"/usr/sbin/networksetup -setairportpower \(device) \(argument)\" with administrator privileges"
        if let output = shell("/usr/bin/osascript", ["-e", script]) {
            return output.isEmpty ? nil : output
        }
        return "Wi-Fi toggle was refused by macOS."
    }
}

// MARK: - Appearance (dark mode)

enum SystemAppearance {
    static func isDark() -> Bool {
        (shell("/usr/bin/defaults", ["read", "-g", "AppleInterfaceStyle"]) ?? "").contains("Dark")
    }

    /// System Events is the only public way to flip the system appearance.
    /// First use triggers the Automation prompt.
    static func toggle() -> String? {
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        if let output = shell("/usr/bin/osascript", ["-e", script]) {
            return output.isEmpty ? nil : output
        }
        return "Toggling dark mode needs Automation permission for System Events."
    }
}

// MARK: - AirDrop
//
// macOS removed the scriptable AirDrop visibility preference: the
// com.apple.NetworkBrowser domain is gone on this system, and Control Center's
// AirDrop picker has no public API. Rather than fake a toggle, the button opens
// the AirDrop & Handoff settings pane.

enum AirDrop {
    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension",
            "x-apple.systempreferences:com.apple.settings.general"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}

// MARK: - Volume (public CoreAudio API)

enum SystemVolume {
    static func defaultDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : nil
    }

    static func level() -> Float? {
        guard let device = defaultDevice() else { return nil }
        if let value: Float = read(device, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain) {
            return value
        }
        // Built-in output exposes per-channel volume instead of a master.
        if let left: Float = read(device, kAudioDevicePropertyVolumeScalar, 1) { return left }
        return nil
    }

    static func setLevel(_ value: Float) {
        guard let device = defaultDevice() else { return }
        let clamped = min(max(value, 0), 1)
        if write(device, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain, clamped) { return }
        _ = write(device, kAudioDevicePropertyVolumeScalar, 1, clamped)
        _ = write(device, kAudioDevicePropertyVolumeScalar, 2, clamped)
    }

    static func isMuted() -> Bool {
        guard let device = defaultDevice(),
              let value: UInt32 = read(device, kAudioDevicePropertyMute, kAudioObjectPropertyElementMain) else { return false }
        return value == 1
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultDevice() else { return }
        _ = write(device, kAudioDevicePropertyMute, kAudioObjectPropertyElementMain, UInt32(muted ? 1 : 0))
    }

    private static func address(_ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput, mElement: element)
    }

    private static func read<T>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> T? {
        var address = address(selector, element)
        var size = UInt32(MemoryLayout<T>.size)
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { buffer.deallocate() }
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer)
        return status == noErr ? buffer.pointee : nil
    }

    private static func write<T>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement, _ value: T) -> Bool {
        var address = address(selector, element)
        var mutable = value
        let size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &mutable) { pointer -> OSStatus in
            AudioObjectSetPropertyData(device, &address, 0, nil, size, pointer)
        }
        return status == noErr
    }
}

// MARK: - Brightness (private DisplayServices framework)
//
// macOS has no public brightness API. This loads the private framework the
// system itself uses; if the symbols are missing the control is disabled and
// says so, rather than pretending to work. Internal display only.

enum DisplayBrightness {
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private static let setFunction: SetFunction? = {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: SetFunction.self)
    }()

    private static let getFunction: GetFunction? = {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetFunction.self)
    }()

    static var available: Bool { setFunction != nil && getFunction != nil }

    static func level() -> Float? {
        guard let getFunction else { return nil }
        var value: Float = 0
        let display = CGMainDisplayID()
        guard getFunction(display, &value) == 0 else { return nil }
        return value
    }

    static func setLevel(_ value: Float) {
        guard let setFunction else { return }
        _ = setFunction(CGMainDisplayID(), min(max(value, 0.05), 1))
    }
}
