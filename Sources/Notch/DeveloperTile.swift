import AppKit
import SwiftUI

struct DeveloperTile: View {
    @ObservedObject var model: IslandModel
    let width: CGFloat
    private var theme: Theme { model.theme }

    var body: some View {
        TileBox(theme: theme) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: model.claude.step.symbol).foregroundStyle(theme.accent)
                    Text("Claude Code").font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Circle().fill(model.claude.socketUp ? theme.accent : theme.warningOrange)
                        .frame(width: 5, height: 5)
                }
                if model.claude.isWorking {
                    Text(model.claude.step.label).foregroundStyle(theme.accent)
                        .font(.system(size: 13, weight: .medium))
                    if let latest = model.claude.activity.first {
                        Text(latest.detail.isEmpty ? latest.tool : latest.detail)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.secondaryText).lineLimit(model.settings.density == .compact ? 1 : 2)
                            .help(latest.detail)
                    }
                } else if let finished = model.claude.lastFinished {
                    Text("Finished in \(IslandModel.duration(finished.duration))")
                        .font(.system(size: 12, weight: .medium))
                    Text(finished.at, style: .time).font(.system(size: 10)).foregroundStyle(theme.secondaryText)
                } else {
                    Text(model.claude.socketUp ? "Ready for your next session" : "Bridge unavailable")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryText).lineLimit(model.settings.density == .compact ? 1 : 2)
                    Button("Set up hooks…") { SettingsWindowController.shared.show(model: model, section: "Developer") }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.accent)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.text)
            .padding(10)
        }
        .help("Recent tool calls stay in memory for this launch. Configure hooks in Settings → Developer.")
    }
}

/// One-cell tiles use a deliberately minimal layout rather than squeezing
/// wide controls and permission copy into a 76-point column.
struct MiniTile: View {
    @ObservedObject var model: IslandModel
    let id: TileID
    private var value: String {
        switch id {
        case .music: return model.music.isPlaying ? "Playing" : "Music"
        case .weather: return model.weather.snapshot.map { "\(Int($0.temperature.rounded()))°" } ?? "Weather"
        case .messages: return "\(model.messages.rows.reduce(0) { $0 + $1.unread }) unread"
        case .controls: return "Apps"
        case .calendar: return "Calendar"
        case .timer: return model.focusTimer.remaining.mmss
        case .developer: return model.claude.step.label
        case .launcher: return "Launch"
        }
    }
    var body: some View {
        TileBox(theme: model.theme) {
            Button {
                switch id {
                case .music: model.music.playPause()
                case .timer: model.focusTimer.running ? model.focusTimer.pause() : model.focusTimer.start()
                case .controls, .launcher: model.showAppGrid()
                default: SettingsWindowController.shared.show(model: model)
                }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: id.symbol).font(.system(size: 17)).foregroundStyle(model.theme.accent)
                    Text(value).font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(model.theme.text).lineLimit(1).minimumScaleFactor(0.8)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(IslandButtonStyle(theme: model.theme))
                .accessibilityLabel("\(id.title), \(value)")
        }
    }
}

struct LauncherTile: View {
    @ObservedObject var model: IslandModel
    private var apps: [(String, String)] {
        switch model.settings.workspace {
        case .developer: return [("Terminal", "com.apple.Terminal"), ("Xcode", "com.apple.dt.Xcode"), ("VS Code", "com.microsoft.VSCode")]
        case .media: return [("Music", "com.apple.Music"), ("Spotify", "com.spotify.client"), ("QuickTime", "com.apple.QuickTimePlayerX")]
        case .focus: return [("Notes", "com.apple.Notes"), ("Reminders", "com.apple.reminders"), ("Calendar", "com.apple.iCal")]
        case .everyday: return [("Finder", "com.apple.finder"), ("Safari", "com.apple.Safari"), ("Notes", "com.apple.Notes")]
        }
    }
    var body: some View {
        TileBox(theme: model.theme) {
            VStack(alignment: .leading, spacing: 10) {
                if model.settings.density == .comfortable {
                    HStack {
                        Text("Quick launch").font(.system(size: 11, weight: .semibold)).foregroundStyle(model.theme.secondaryText)
                        Spacer()
                        Button("All apps") { model.showAppGrid() }.buttonStyle(.plain)
                            .font(.system(size: 10)).foregroundStyle(model.theme.accent)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(apps, id: \.1) { name, bundle in
                        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
                        Button {
                            guard let url else { return }
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                        } label: {
                            VStack(spacing: 5) {
                                if let url {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable().scaledToFit().frame(width: 24, height: 24)
                                } else {
                                    Image(systemName: "app.dashed").font(.system(size: 22)).frame(height: 24)
                                }
                                Text(name).font(.system(size: 9)).lineLimit(1)
                            }.frame(maxWidth: .infinity).padding(.vertical, 4)
                                .foregroundStyle(model.theme.text)
                        }.buttonStyle(IslandButtonStyle(theme: model.theme))
                            .disabled(url == nil).opacity(url == nil ? 0.35 : 1)
                            .help(url == nil ? "\(name) isn’t installed" : "Open \(name)")
                    }
                }
            }.padding(10)
        }
    }
}
