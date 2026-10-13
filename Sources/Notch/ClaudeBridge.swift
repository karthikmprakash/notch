import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Permission card

struct PermissionCard: Equatable {
    var id: String
    var tool: String
    var command: String
    var summary: String?
    var session: String
    var received: Date

    var headline: String {
        switch tool {
        case "Bash": return "Claude wants to run a command"
        case "Write", "Edit", "MultiEdit", "NotebookEdit": return "Claude wants to edit a file"
        case "WebFetch", "WebSearch": return "Claude wants to use the network"
        default: return "Claude needs permission · \(tool)"
        }
    }
}

// MARK: - Global hotkeys (Carbon, so no Accessibility permission is needed)

final class HotKeys {
    static let shared = HotKeys()

    var onAllow: (() -> Void)?
    var onDeny: (() -> Void)?
    var onToggleIsland: (() -> Void)?
    private var toggleRef: EventHotKeyRef?

    private var allowRef: EventHotKeyRef?
    private var denyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var registered = false

    private static let signature: OSType = 0x4E4F5443  // 'NOTC'

    func register() {
        guard !registered else { return }
        registered = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &id)
            guard status == noErr else { return status }
            switch id.id {
            case 1: HotKeys.shared.onAllow?()
            case 2: HotKeys.shared.onDeny?()
            case 3: HotKeys.shared.onToggleIsland?()
            default: break
            }
            return noErr
        }, 1, &eventType, nil, &handlerRef)

        let toggleID = EventHotKeyID(signature: Self.signature, id: 3)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), toggleID,
                            GetApplicationEventTarget(), 0, &toggleRef)
        let allowID = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey), allowID,
                            GetApplicationEventTarget(), 0, &allowRef)
        let denyID = EventHotKeyID(signature: Self.signature, id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey), denyID,
                            GetApplicationEventTarget(), 0, &denyRef)
    }
}

// MARK: - Claude Code bridge

@MainActor
final class ClaudeBridge: ObservableObject {
    enum Step: Equatable {
        case idle
        case reading
        case editing
        case running
        case searching
        case thinking

        var symbol: String {
            switch self {
            case .reading: return "doc.text"
            case .editing: return "pencil"
            case .running: return "terminal"
            case .searching: return "magnifyingglass"
            default: return "sparkle"
            }
        }

        var label: String {
            switch self {
            case .reading: return "Reading"
            case .editing: return "Editing"
            case .running: return "Running"
            case .searching: return "Searching"
            case .thinking: return "Working"
            case .idle: return "Idle"
            }
        }
    }

    enum Decision: String {
        case allow, deny
    }

    struct Finished: Equatable {
        var duration: TimeInterval
        var at: Date
    }

    enum Event {
        case notify(String)
        case finished(Finished)
    }

    @Published private(set) var step: Step = .idle
    @Published private(set) var isWorking = false
    @Published private(set) var card: PermissionCard?
    @Published private(set) var lastFinished: Finished?
    struct Activity: Identifiable {
        let id = UUID()
        let tool: String
        let detail: String
        let at: Date
    }
    @Published private(set) var activity: [Activity] = []
    @Published private(set) var socketUp = false

    var onEvent: ((Event) -> Void)?

    private var server: UnixSocketServer?
    private var pending: (id: String, connection: UnixConnection)?
    private var sessionStarts: [String: Date] = [:]
    private var idleWork: DispatchWorkItem?
    private var cardTimer: DispatchWorkItem?

    func start() {
        startServer()
        HotKeys.shared.onAllow = { [weak self] in self?.resolve(.allow, fromHotkey: true) }
        HotKeys.shared.onDeny = { [weak self] in self?.resolve(.deny, fromHotkey: true) }
        HotKeys.shared.register()
    }

    private func startServer() {
        let server = UnixSocketServer(path: AppPaths.socket.path)
        server.handler = { [weak self] connection, line in
            self?.handle(line: line, connection: connection)
        }
        do {
            try server.start()
            self.server = server
            socketUp = true
        } catch {
            socketUp = false
            NSLog("Notch: claude socket failed: \(error)")
        }
    }

    // MARK: Incoming hook messages

    private func handle(line: String, connection: UnixConnection) {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = root["event"] as? String else {
            connection.close()
            return
        }

        let session = root["session"] as? String ?? ""
        let tool = root["tool"] as? String ?? ""
        let detail = root["detail"] as? String ?? ""
        let summary = root["summary"] as? String

        switch event {
        case "PreToolUse":
            activity.insert(Activity(tool: tool, detail: detail, at: Date()), at: 0)
            if activity.count > 30 { activity.removeLast(activity.count - 30) }
            if sessionStarts[session] == nil { sessionStarts[session] = Date() }
            step = Self.step(for: tool)
            isWorking = true
            scheduleIdleReset()
            connection.close()

        case "PostToolUse":
            scheduleIdleReset()
            connection.close()

        case "PermissionRequest":
            let card = PermissionCard(id: root["id"] as? String ?? UUID().uuidString,
                                      tool: tool.isEmpty ? "tool" : tool,
                                      command: detail.isEmpty ? (summary ?? tool) : detail,
                                      summary: summary,
                                      session: session,
                                      received: Date())
            pending?.connection.close()
            pending = (card.id, connection)
            withAnimation(IslandModel.Layout.spring) { self.card = card }
            isWorking = true
            scheduleCardTimeout()
            onEvent?(.notify("Claude needs permission"))
            // Dev-only: `NOTCH_DEBUG_AUTOALLOW=1` answers by itself so the whole
            // hook round-trip can be tested without a mouse.
            if ProcessInfo.processInfo.environment["NOTCH_DEBUG_AUTOALLOW"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.resolve(.allow)
                }
            }

        case "Notification":
            let text = root["message"] as? String ?? "Claude needs your input"
            connection.close()
            onEvent?(.notify(text))

        case "Stop", "SessionEnd":
            connection.close()
            let duration = Date().timeIntervalSince(sessionStarts[session] ?? Date())
            sessionStarts[session] = nil
            isWorking = false
            step = .idle
            idleWork?.cancel()
            if event == "Stop" {
                let finished = Finished(duration: duration, at: Date())
                lastFinished = finished
                onEvent?(.finished(finished))
            }

        default:
            connection.close()
        }
    }

    private func scheduleIdleReset() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isWorking = false
            self.step = .idle
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    private func scheduleCardTimeout() {
        cardTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Nobody answered: let Claude Code fall back to its own prompt.
            self.pending?.connection.close()
            self.pending = nil
            withAnimation(IslandModel.Layout.spring) { self.card = nil }
        }
        cardTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 100, execute: work)
    }

    // MARK: Deciding

    func resolve(_ decision: Decision, fromHotkey: Bool = false) {
        guard let pending else { return }
        cardTimer?.cancel()
        pending.connection.reply("{\"decision\":\"\(decision.rawValue)\"}")
        self.pending = nil
        withAnimation(IslandModel.Layout.spring) { card = nil }
        if decision == .allow {
            isWorking = true
            step = .running
            scheduleIdleReset()
        } else {
            isWorking = false
            step = .idle
        }
    }

    static func step(for tool: String) -> Step {
        switch tool {
        case "Read", "NotebookRead": return .reading
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return .editing
        case "Bash", "BashOutput", "KillShell": return .running
        case "Grep", "Glob", "WebSearch", "WebFetch": return .searching
        default: return .thinking
        }
    }
}
