import AppKit
import SwiftUI

// MARK: - Settings window

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var hosting: NSHostingView<SettingsView>?

    func show(model: IslandModel, section: String? = nil) {
        if let window {
            if let section { hosting?.rootView = SettingsView(model: model, section: section) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(model: model, section: section ?? "Workspace")
        let hosting = NSHostingView(rootView: view)
        self.hosting = hosting
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Notch · Settings"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .normal
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var settings = SettingsStore.shared

    @State private var tab: String

    init(model: IslandModel, section: String = "Workspace") {
        self.model = model
        _tab = State(initialValue: section)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "capsule.fill")
                    .font(.system(size: 24)).foregroundStyle(model.theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("A space for every way you work").font(.system(size: 20, weight: .semibold))
                    Text("Notch · \(settings.workspace.title) workspace").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Picker("Settings section", selection: $tab) {
                ForEach(["Workspace", "Integrations", "General", "Developer"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case "Workspace": workspaceSection; themeSection; tilesSection
                    case "Integrations": weatherSection; privacySection; diagnosticsSection
                    case "General": generalSection; peeksSection
                    default: claudeSection; activitySection
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 600, minHeight: 600)
        .preferredColorScheme(model.theme.isDark ? .dark : .light)
        .tint(model.theme.accent)
    }

    private var workspaceSection: some View {
        Section(title: "Workspace") {
            HStack(spacing: 8) {
                ForEach(Workspace.allCases) { workspace in
                    Button { settings.selectWorkspace(workspace) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: workspace.symbol).font(.system(size: 20))
                            Text(workspace.title).font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity).frame(height: 68)
                        .foregroundStyle(settings.workspace == workspace ? model.theme.accent : model.theme.secondaryText)
                        .background(RoundedRectangle(cornerRadius: 10).fill(settings.workspace == workspace ? model.theme.accent.opacity(0.12) : model.theme.control))
                    }.buttonStyle(.plain)
                }
            }
            Text(settings.workspace.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Picker("Layout", selection: $settings.layout) {
                    ForEach(DashboardLayout.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Density", selection: $settings.density) {
                    ForEach(DashboardDensity.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            }.padding(.top, 6)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(settings.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 4) {
                            ForEach(row) { config in
                                RoundedRectangle(cornerRadius: 3).fill(model.theme.accent.opacity(0.25))
                                    .frame(width: CGFloat(config.cells) * 16, height: settings.density == .compact ? 12 : 20)
                            }
                        }
                    }
                }
                Text("Changes save to this workspace. Switch freely; every layout stays yours.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.top, 8)
            Button("Open dashboard") { model.showDashboard() }
        }
    }

    private var activitySection: some View {
        Section(title: "Recent activity · this launch") {
            if model.claude.activity.isEmpty {
                Text("Tool calls appear here once Claude Code sends hook events.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ForEach(model.claude.activity.prefix(12)) { activity in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(activity.tool, systemImage: ClaudeBridge.step(for: activity.tool).symbol)
                            Spacer()
                            Text(activity.at, style: .time).foregroundStyle(.secondary)
                        }.font(.system(size: 11, weight: .medium))
                        Text(activity.detail).font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: Sections

    private var themeSection: some View {
        Section(title: "Appearance") {
            Picker("", selection: $settings.themeKind) {
                ForEach(ThemeKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var weatherSection: some View {
        Section(title: "Weather city") {
            HStack(spacing: 8) {
                TextField("City", text: $settings.city)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button("Update") {
                    model.weather.setCity(settings.city)
                }
                Text(statusText(for: model.weather.status))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tilesSection: some View {
        Section(title: "Tiles · \(settings.workspace.title)") {
            VStack(spacing: 4) {
                ForEach(Array(settings.tiles.enumerated()), id: \.element.id) { index, tile in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { settings.tiles[index].visible },
                            set: { settings.tiles[index].visible = $0 }
                        ))
                        .labelsHidden()
                        .accessibilityLabel("Show \(tile.id.title)")
                        .toggleStyle(.checkbox)

                        Image(systemName: tile.id.symbol).frame(width: 18)
                        Text(tile.id.title).frame(width: 110, alignment: .leading)

                        Picker("", selection: Binding(
                            get: { settings.tiles[index].cells },
                            set: { settings.tiles[index].cells = $0 }
                        )) {
                            Text("Small").tag(1)
                            Text("Medium").tag(2)
                            Text("Wide").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 190)

                        Spacer(minLength: 0)

                        Button {
                            move(from: index, to: index - 1)
                        } label: { Image(systemName: "arrow.up") }
                            .disabled(index == 0)

                        Button {
                            move(from: index, to: index + 1)
                        } label: { Image(systemName: "arrow.down") }
                            .disabled(index == settings.tiles.count - 1)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Restore this workspace’s defaults") { settings.resetTiles() }
                .font(.system(size: 11))
                .padding(.top, 4)
        }
    }

    private func move(from index: Int, to target: Int) {
        guard target >= 0, target < settings.tiles.count else { return }
        var tiles = settings.tiles
        let item = tiles.remove(at: index)
        tiles.insert(item, at: target)
        settings.tiles = tiles
    }

    private var peeksSection: some View {
        Section(title: "Peeks") {
            Toggle("Apps open and quit", isOn: Binding(
                get: { settings.peeks.apps },
                set: { settings.peeks.apps = $0 }))
            Toggle("Charger, and battery at 20 % and 10 %", isOn: Binding(
                get: { settings.peeks.power },
                set: { settings.peeks.power = $0 }))
            HStack(spacing: 8) {
                Toggle("Do Not Disturb on and off", isOn: Binding(
                    get: { settings.peeks.focus },
                    set: { settings.peeks.focus = $0 }))
                Text(model.focusStatusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generalSection: some View {
        Section(title: "General") {
            Toggle("Start at login", isOn: $settings.launchAtLogin)
        }
    }

    private var privacySection: some View {
        Section(title: "Privacy") {
            Toggle("Fetch Spotify cover art (one image request per track)", isOn: $settings.fetchSpotifyArtwork)
            Text("Otherwise nothing leaves this Mac except the city you type above (Open-Meteo) and the song you are playing (LRCLIB). Apple Music artwork is read locally.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var claudeSection: some View {
        Section(title: "Claude Code") {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.claude.socketUp
                     ? "Socket up at ~/Library/Application Support/Notch/notch.sock"
                     : "Socket failed to start — see the log")
                    .font(.system(size: 11))
                    .foregroundStyle(model.claude.socketUp ? Color.secondary : Color.red)

                HStack {
                    Text("Add this to ~/.claude/settings.json yourself:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(hooksSnippet, forType: .string)
                    }
                }

                ScrollView {
                    Text(hooksSnippet)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 190)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.06)))

                Text("Global shortcuts while a permission card is open: ⌃⌥A allow, ⌃⌥D deny. Both use Carbon hot keys, so no Accessibility permission is needed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var diagnosticsSection: some View {
        Section(title: "Status") {
            VStack(alignment: .leading, spacing: 3) {
                line("Music", statusText(for: model.music.status))
                line("Weather", statusText(for: model.weather.status))
                line("Messages", statusText(for: model.messages.status))
                line("Calendar", statusText(for: model.calendar.status))
                line("Brightness", model.controls.brightnessAvailable ? "available" : "not available on this display")
                line("Launch at login", LaunchAtLogin.isEnabled ? "on" : "off")
            }
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium)).frame(width: 110, alignment: .leading)
            Text(value).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func statusText(for status: MusicService.Status) -> String {
        switch status {
        case .noPlayer: return "no player running"
        case .playing: return "playing"
        case .paused: return "paused"
        case .automationDenied: return "Automation permission denied"
        }
    }

    private func statusText(for status: WeatherService.Status) -> String {
        switch status {
        case .idle: return "idle"
        case .loading: return "loading"
        case .ok: return "ok"
        case .unknownCity: return "city not found"
        case .offline: return "offline"
        }
    }

    private func statusText(for status: MessagesService.Status) -> String {
        switch status {
        case .idle: return "idle"
        case .ok: return "ok"
        case .needsFullDiskAccess: return "Full Disk Access required"
        case .error(let message): return message
        }
    }

    private func statusText(for status: CalendarService.Status) -> String {
        switch status {
        case .idle: return "idle"
        case .notAsked: return "permission not requested yet"
        case .granted: return "granted"
        case .denied: return "denied"
        }
    }

    // MARK: Hooks snippet

    var hooksSnippet: String {
        let binary = Bundle.main.executablePath ?? "/path/to/Notch.app/Contents/MacOS/Notch"
        return """
        {
          "hooks": {
            "PreToolUse": [
              { "hooks": [ { "type": "command", "command": "\(binary) --hook", "timeout": 5 } ] }
            ],
            "PostToolUse": [
              { "hooks": [ { "type": "command", "command": "\(binary) --hook", "timeout": 5 } ] }
            ],
            "Notification": [
              { "hooks": [ { "type": "command", "command": "\(binary) --hook", "timeout": 5 } ] }
            ],
            "PermissionRequest": [
              { "hooks": [ { "type": "command", "command": "\(binary) --hook", "timeout": 120 } ] }
            ],
            "Stop": [
              { "hooks": [ { "type": "command", "command": "\(binary) --hook", "timeout": 5 } ] }
            ]
          }
        }
        """
    }
}

struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
}
