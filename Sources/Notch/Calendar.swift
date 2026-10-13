import AppKit
import EventKit
import SwiftUI

// MARK: - Calendar (EventKit, asked for only when the tile is switched on)

@MainActor
final class CalendarService: ObservableObject {
    struct Event: Equatable {
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var calendarName: String
        var color: NSColor
    }

    enum Status: Equatable {
        case idle
        case notAsked
        case granted
        case denied
    }

    @Published private(set) var next: Event?
    @Published private(set) var status: Status = .idle

    private let store = EKEventStore()
    private var timer: Timer?

    func start() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            status = .granted
            refresh()
        case .notDetermined:
            status = .notAsked
        default:
            status = .denied
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Asked the first time the calendar tile is switched on.
    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                self.status = granted ? .granted : .denied
                self.refresh()
            }
        }
    }

    func refresh() {
        guard status == .granted else { return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        guard let event = events.first else {
            next = nil
            return
        }
        next = Event(
            title: event.title ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarName: event.calendar.title,
            color: event.calendar.color
        )
    }

    /// "now", "in 12m", "14:30" …
    static func whenText(for event: Event, now: Date = Date()) -> String {
        if event.isAllDay {
            return Calendar.current.isDateInToday(event.start) ? "All day" : "All day · \(event.start.shortStamp(now: now))"
        }
        if event.start <= now {
            return "Now · ends \(Self.time(event.end))"
        }
        let delta = event.start.timeIntervalSince(now)
        if delta < 3600 {
            return "in \(max(1, Int(delta / 60)))m · \(Self.time(event.start))"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(event.start) ? "HH:mm" : "EEE HH:mm"
        return formatter.string(from: event.start)
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Focus timer (25 minutes)

@MainActor
final class FocusTimer: ObservableObject {
    static let duration: TimeInterval = 25 * 60

    @Published private(set) var remaining: TimeInterval = FocusTimer.duration
    @Published private(set) var running = false
    @Published private(set) var sessionDuration: TimeInterval = FocusTimer.duration
    var onFinished: (() -> Void)?

    private var timer: Timer?
    private var endDate: Date?

    var progress: Double {
        1 - (remaining / sessionDuration)
    }

    var isFinished: Bool { remaining <= 0 }

    func start() {
        guard !running else { return }
        if remaining <= 0 { remaining = sessionDuration }
        running = true
        endDate = Date().addingTimeInterval(remaining)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        running = false
        timer?.invalidate()
        timer = nil
        if let endDate { remaining = max(0, endDate.timeIntervalSinceNow) }
    }

    func reset() {
        pause()
        remaining = sessionDuration
        endDate = nil
    }

    func setMinutes(_ minutes: Int) {
        pause()
        sessionDuration = TimeInterval(min(max(minutes, 1), 120) * 60)
        reset()
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            onFinished?()
            running = false
            timer?.invalidate()
            timer = nil
        }
    }
}
