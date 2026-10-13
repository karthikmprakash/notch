import AppKit
import SwiftUI

/// Observable front end for the system controls, refreshed lazily.
@MainActor
final class SystemControls: ObservableObject {
    @Published private(set) var wifiOn = true
    @Published private(set) var darkMode = false
    @Published private(set) var volume: Float = 0.5
    @Published private(set) var muted = false
    @Published private(set) var brightness: Float = 0.5
    @Published private(set) var brightnessAvailable = DisplayBrightness.available
    @Published private(set) var lastError: String?

    private var timer: Timer?

    func start() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        if let on = WiFi.isOn() { wifiOn = on }
        darkMode = SystemAppearance.isDark()
        if let level = SystemVolume.level(), !muted { volume = level }
        muted = SystemVolume.isMuted()
        if let level = DisplayBrightness.level() { brightness = level }
        brightnessAvailable = DisplayBrightness.available
    }

    // MARK: Actions

    func toggleWiFi() {
        let target = !wifiOn
        lastError = WiFi.set(target)
        if lastError == nil { wifiOn = target }
        if let lastError { NSLog("Notch: Wi-Fi toggle: \(lastError)") }
    }

    func toggleDarkMode() {
        lastError = SystemAppearance.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refresh()
        }
    }

    func openAirDrop() {
        // AirDrop visibility has no public API on this macOS version; the button
        // opens the AirDrop & Handoff pane instead of pretending to toggle.
        AirDrop.openSettings()
    }

    func setVolume(_ value: Float) {
        volume = min(max(value, 0), 1)
        SystemVolume.setLevel(volume)
        if muted, volume > 0 {
            muted = false
            SystemVolume.setMuted(false)
        }
    }

    func toggleMute() {
        muted.toggle()
        SystemVolume.setMuted(muted)
    }

    func setBrightness(_ value: Float) {
        brightness = min(max(value, 0.05), 1)
        DisplayBrightness.setLevel(brightness)
    }

    func cycleBrightness() {
        let presets: [Float] = [1.0, 0.75, 0.5, 0.25]
        let next = presets.first(where: { $0 < brightness - 0.02 }) ?? presets[0]
        setBrightness(next)
    }
}
