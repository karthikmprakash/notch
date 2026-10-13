import AppKit
import IOKit.ps
import Intents
import SwiftUI

// MARK: - Power (charger + battery levels)

@MainActor
final class PowerMonitor: ObservableObject {
    enum Event: Equatable {
        case pluggedIn
        case unplugged
        case lowBattery(Int)
    }

    var onEvent: ((Event) -> Void)?

    private var source: CFRunLoopSource?
    private var lastOnAC: Bool?
    private var firedLevels: Set<Int> = []

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.evaluate() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.source = source
        }
        evaluate(initial: true)
    }

    private func evaluate(initial: Bool = false) {
        guard let snapshot = Self.current() else { return }
        if let last = lastOnAC, last != snapshot.onAC, !initial {
            onEvent?(snapshot.onAC ? .pluggedIn : .unplugged)
        }
        lastOnAC = snapshot.onAC

        if !snapshot.onAC, let percentage = snapshot.percentage {
            for level in [20, 10] where percentage <= level {
                if !firedLevels.contains(level) {
                    firedLevels.insert(level)
                    onEvent?(.lowBattery(level))
                }
            }
            if percentage > 25 { firedLevels.removeAll() }
        } else if snapshot.onAC {
            firedLevels.removeAll()
        }
    }

    static func current() -> (onAC: Bool, percentage: Int?, charging: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue() as? [String: Any] else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String ?? ""
            let percentage = description[kIOPSCurrentCapacityKey] as? Int
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            return (state == kIOPSACPowerValue, percentage, charging)
        }
        return nil
    }
}

// MARK: - Focus / Do Not Disturb
//
// There is no public API to toggle Focus, and reading it needs the Focus status
// permission. When it is not granted the app says so instead of guessing.

@MainActor
final class FocusMonitor: ObservableObject {
    enum Status: Equatable {
        case unknown
        case authorized
        case denied
    }

    var onEvent: ((Bool) -> Void)?

    @Published private(set) var status: Status = .unknown
    @Published private(set) var isFocused: Bool?

    private var timer: Timer?
    private var last: Bool?

    func start() {
        INFocusStatusCenter.default.requestAuthorization { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                self.status = result == .authorized ? .authorized : .denied
                self.poll()
            }
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard status == .authorized else { return }
        let focused = INFocusStatusCenter.default.focusStatus.isFocused
        isFocused = focused
        if let focused, let last, last != focused {
            onEvent?(focused)
        }
        last = focused
    }
}

// MARK: - Peek centre: app launch/quit, charger, battery, Focus

@MainActor
final class PeekCenter {
    var onPeek: ((PeekPayload) -> Void)?

    private let power = PowerMonitor()
    private let focus = FocusMonitor()
    private var observers: [NSObjectProtocol] = []
    private weak var settings: SettingsStore?

    func start(settings: SettingsStore) {
        self.settings = settings
        focus.start()
        focus.onEvent = { [weak self] focused in
            guard settings.peeks.focus else { return }
            self?.onPeek?(PeekPayload(
                symbol: "moon.zzz.fill",
                title: focused ? "Do Not Disturb on" : "Do Not Disturb off",
                subtitle: nil,
                warning: false))
        }

        power.onEvent = { [weak self] event in
            guard settings.peeks.power else { return }
            switch event {
            case .pluggedIn:
                self?.onPeek?(PeekPayload(symbol: "powerplug.fill", title: "Charger connected", subtitle: nil))
            case .unplugged:
                self?.onPeek?(PeekPayload(symbol: "battery.100percent", title: "On battery", subtitle: nil))
            case .lowBattery(let level):
                self?.onPeek?(PeekPayload(symbol: "battery.25percent",
                                          title: "Battery at \(level)%",
                                          subtitle: "Plug in soon",
                                          warning: true))
            }
        }
        power.start()

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, settings.peeks.apps,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self.peekForApplication(app, launched: true)
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, settings.peeks.apps,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self.peekForApplication(app, launched: false)
            }
        })
    }

    private func peekForApplication(_ app: NSRunningApplication, launched: Bool) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        guard app.activationPolicy == .regular else { return }
        let name = app.localizedName ?? app.bundleIdentifier ?? "App"
        var icon: NSImage?
        if let url = app.bundleURL {
            icon = NSWorkspace.shared.icon(forFile: url.path)
            icon?.size = NSSize(width: 64, height: 64)
        }
        onPeek?(PeekPayload(symbol: nil,
                            title: name,
                            subtitle: launched ? "Opened" : "Quit",
                            icon: icon))
    }

    func refreshFocusStatus() {
        focus.start()
    }

    var focusStatus: FocusMonitor.Status { focus.status }
    var isFocusedNow: Bool { focus.isFocused ?? false }
}
