import AppKit
import SwiftUI

// MARK: - Tile chrome
//
// Every tile is clipped to its own rounded rectangle. The blurred music
// background is blurred *inside* the tile's frame and clipped after, so the
// blur can never spill out and leave a light frame inside the tile.

struct TileBox<Background: View, Content: View>: View {
    let theme: Theme
    var radius: CGFloat = 10
    @ViewBuilder var background: Background
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                background
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(theme.tileStroke, lineWidth: 1)
            }
    }
}

extension TileBox where Background == Color {
    init(theme: Theme, radius: CGFloat = 10, content: () -> Content) {
        self.init(theme: theme, radius: radius, background: { theme.tile }, content: content)
    }
}

// MARK: - Small shared pieces

struct AccentBadge: View {
    let count: Int
    let theme: Theme

    var body: some View {
        Text("\(count)")
            .font(.system(size: 9.5, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(theme.isDark ? Color(hex: 0x10131A) : .white)
            .padding(.horizontal, 4)
            .frame(minWidth: 15, minHeight: 15)
            .background(Capsule().fill(theme.accent))
    }
}

struct ProgressLine: View {
    let value: Double
    let theme: Theme
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.track)
                Capsule().fill(theme.trackFill)
                    .frame(width: max(0, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// Small round button used inside tiles.
struct TileButton: View {
    let symbol: String
    var size: CGFloat = 12
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandButtonStyle(theme: Theme.of(SettingsStore.shared.themeKind)))
        .accessibilityLabel(accessibleTitle)
        .help(accessibleTitle)
    }

    private var accessibleTitle: String {
        switch symbol {
        case "backward.fill": return "Previous track"
        case "forward.fill": return "Next track"
        case "play.fill": return "Play or start"
        case "pause.fill": return "Pause"
        case "arrow.counterclockwise": return "Reset timer"
        default: return symbol
        }
    }
}

// MARK: - Music

struct MusicTile: View {
    @ObservedObject var model: IslandModel
    var width: CGFloat

    private var music: MusicService { model.music }
    private var theme: Theme { model.theme }
    private var compact: Bool { width < 150 }

    var body: some View {
        TileBox(theme: theme, background: { background }) {
            content
                .padding(.horizontal, 10)
                .padding(.vertical, model.settings.density == .compact ? 6 : 10)
        }
    }

    @ViewBuilder
    private var background: some View {
        // Dark Matte: the blurred cover fills the whole tile. White Matte keeps
        // the flat light tile like every other tile.
        if theme.isDark, let artwork = music.artwork {
            ZStack {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 26, opaque: true)
                    .overlay(Color.black.opacity(0.42))
            }
        } else {
            theme.tile
        }
    }

    @ViewBuilder
    private var content: some View {
        if music.status == .noPlayer {
            VStack(alignment: .leading, spacing: 8) {
                Label("Your soundtrack", systemImage: "music.note").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text)
                Text("Play something in Spotify or Music.").font(.system(size: 11)).foregroundStyle(theme.secondaryText)
            }
        } else if music.status == .automationDenied {
            VStack(alignment: .leading, spacing: 3) {
                Text("Automation not allowed").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text)
                Text("System Settings → Privacy → Automation → Notch → Spotify / Music")
                    .font(.system(size: 10)).foregroundStyle(theme.secondaryText).lineLimit(3)
            }
        } else if let track = music.track {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Vinyl(artwork: music.artwork, theme: theme, size: model.settings.density == .comfortable ? 48 : 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.text).lineLimit(1).help(track.title)
                        Text(track.artist).font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText).lineLimit(1)
                        if model.settings.density == .comfortable { lyricLine }
                    }
                }
                ProgressLine(value: music.progress, theme: theme).frame(height: 3)
                HStack(spacing: 2) {
                    Text(music.position.mmss).font(.system(size: 9)).monospacedDigit().foregroundStyle(theme.secondaryText)
                    Spacer(minLength: 0)
                    transport
                    Spacer(minLength: 0)
                    Text(track.duration.mmss).font(.system(size: 9)).monospacedDigit().foregroundStyle(theme.secondaryText)
                }
            }

        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Your soundtrack", systemImage: "music.note").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text)
                Text("Play something in Spotify or Music.").font(.system(size: 11)).foregroundStyle(theme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var lyricLine: some View {
        let line = model.lyrics.line(at: music.position)
        if let line {
            Text(line)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
                .truncationMode(.tail)
                .transition(.opacity)
        } else {
            Text(model.lyrics.status == .loading ? "…" : " ")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
    }

    private var transport: some View {
        HStack(spacing: 2) {
            TileButton(symbol: "backward.fill", size: 11, tint: theme.text) { music.previous() }
            TileButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: 12, tint: theme.text) { music.playPause() }
            TileButton(symbol: "forward.fill", size: 11, tint: theme.text) { music.next() }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.secondaryText)
    }
}

/// The cover as a vinyl record, with the square cover in front — as in the mockup.
struct Vinyl: View {
    let artwork: NSImage?
    let theme: Theme
    var size: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            disc
                .frame(width: size * 0.92, height: size * 0.92)
                .offset(x: size * 0.14)
            cover
                .frame(width: size * 0.8, height: size * 0.8)
        }
        .frame(width: size, height: size, alignment: .leading)
    }

    private var disc: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                theme.control
            }
            Color.black.opacity(0.35)
            // groove highlight + centre label
            Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1).padding(size * 0.12)
            Circle().fill(theme.isDark ? Color.black.opacity(0.55) : Color.white.opacity(0.55))
                .frame(width: size * 0.22, height: size * 0.22)
            Circle().fill(theme.accent).frame(width: size * 0.07, height: size * 0.07)
        }
        .clipShape(Circle())
    }

    private var cover: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                theme.control.overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3))
                        .foregroundStyle(theme.secondaryText)
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
        }
    }
}

// MARK: - Weather

struct WeatherTile: View {
    @ObservedObject var model: IslandModel
    var width: CGFloat

    private var theme: Theme { model.theme }

    var body: some View {
        TileBox(theme: theme) {
            content.padding(10)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.weather.snapshot {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Int(snapshot.temperature.rounded()))°")
                        .font(.system(size: model.settings.density == .compact ? 26 : 32, weight: .regular))
                        .foregroundStyle(theme.text)
                        .monospacedDigit()
                    Text(snapshot.city)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("H \(Int(snapshot.high.rounded()))°   L \(Int(snapshot.low.rounded()))°")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: WeatherService.symbol(for: snapshot.code, isDay: snapshot.isDay))
                    .font(.system(size: width < 160 ? 22 : 26))
                    .foregroundStyle(theme.accent)
                    .padding(.top, 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(model.settings.city.isEmpty ? "Set a city in Settings" : "City: \(model.settings.city)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
            }
        }
    }

    private var statusText: String {
        switch model.weather.status {
        case .unknownCity: return "City not found"
        case .offline: return "Offline"
        case .loading: return "Loading…"
        default: return "No weather yet"
        }
    }
}

// MARK: - Messages

struct MessagesTile: View {
    @ObservedObject var model: IslandModel
    var width: CGFloat

    private var theme: Theme { model.theme }

    var body: some View {
        TileBox(theme: theme) {
            content.padding(10)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.messages.status {
        case .needsFullDiskAccess:
            VStack(alignment: .leading, spacing: 3) {
                Label("Connect Messages", systemImage: "message")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text("Full Disk Access is required.")
                    .font(.system(size: 10)).foregroundStyle(theme.secondaryText)
                Button("Open Privacy Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.accent)
                .help("Add Notch to Full Disk Access, then relaunch it.")
            }
        case .error(let message):
            Text(message).font(.system(size: 11)).foregroundStyle(theme.warningRed).lineLimit(3)
        default:
            if model.messages.rows.isEmpty {
                Text("No unread messages")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(model.messages.rows.prefix(2)) { row in
                        HStack(spacing: 6) {
                            Text(row.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.text)
                                .frame(maxWidth: width * 0.28, alignment: .leading)
                                .lineLimit(1)
                            AccentBadge(count: row.unread, theme: theme)
                            Text(row.preview.isEmpty ? "Attachment" : row.preview)
                                .font(.system(size: 11))
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(row.date.shortStamp())
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Quick controls

struct ControlsTile: View {
    @ObservedObject var model: IslandModel
    var width: CGFloat

    private var theme: Theme { model.theme }
    private var controls: SystemControls { model.controls }

    var body: some View {
        TileBox(theme: theme) {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    controlButton(symbol: "wifi", active: controls.wifiOn, hint: "Wi-Fi", action: controls.toggleWiFi)
                    controlButton(symbol: "dot.radiowaves.left.and.right", active: false, hint: "AirDrop settings", action: controls.openAirDrop)
                    controlButton(symbol: controls.darkMode ? "moon.fill" : "sun.max.fill",
                                  active: controls.darkMode, hint: "Dark mode", action: controls.toggleDarkMode)
                }
                HStack(spacing: 4) {
                    DragControl(symbol: controls.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                value: controls.volume, theme: theme, hint: "Volume",
                                onTap: controls.toggleMute, onChange: controls.setVolume)
                    DragControl(symbol: "sun.max.fill",
                                value: controls.brightness, theme: theme, hint: "Brightness",
                                enabled: controls.brightnessAvailable,
                                onTap: controls.cycleBrightness, onChange: controls.setBrightness)
                    controlButton(symbol: "square.grid.3x3.fill", active: false, hint: "App grid",
                                  action: { model.showAppGrid() })
                }
            }
            .padding(8)
        }
    }

    private func controlButton(symbol: String, active: Bool, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? theme.accent.opacity(theme.isDark ? 0.20 : 0.16) : theme.control)
                VStack(spacing: 3) {
                    Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                    if model.settings.density == .comfortable {
                        Text(hint == "AirDrop settings" ? "AirDrop" : hint == "Dark mode" ? "Theme" : hint == "App grid" ? "Apps" : hint).font(.system(size: 9)).lineLimit(1)
                    }
                }
                .foregroundStyle(active ? theme.accent : theme.secondaryText)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(hint)
        .accessibilityLabel(hint)
    }
}

/// Button that adjusts a level when dragged and runs an action when tapped.
struct DragControl: View {
    let symbol: String
    let value: Float
    let theme: Theme
    var hint: String
    var enabled: Bool = true
    var onTap: () -> Void
    var onChange: (Float) -> Void

    @State private var dragging = false
    @State private var startValue: Float = 0
    @State private var moved: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.control)
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(enabled ? theme.secondaryText : theme.secondaryText.opacity(0.4))
                if dragging || hint == "Volume" || hint == "Brightness" {
                    Text("\(Int((value * 100).rounded()))")
                        .font(.system(size: 8, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.accent.opacity(dragging ? 0.55 : 0.28))
                .frame(height: dragging ? 3 : 2)
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
                .scaleEffect(x: CGFloat(max(0.02, min(value, 1))), anchor: .leading)
                .opacity(dragging ? 1 : 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("\(hint): \(Int(value * 100))%. Drag left or right to adjust.")
        .accessibilityLabel(hint)
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: onChange(min(1, value + 0.05))
            case .decrement: onChange(max(0, value - 0.05))
            @unknown default: break
            }
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { gesture in
                    guard enabled else { return }
                    if !dragging {
                        dragging = true
                        startValue = value
                    }
                    moved = gesture.translation.width
                    let delta = Float(gesture.translation.width / 120)
                    onChange(min(max(startValue + delta, 0), 1))
                }
                .onEnded { _ in
                    dragging = false
                    if abs(moved) < 6, enabled { onTap() }
                    moved = 0
                }
        )
        .onTapGesture { if enabled { onTap() } }
    }
}

// MARK: - Calendar

struct CalendarTile: View {
    @ObservedObject var model: IslandModel
    var width: CGFloat

    private var theme: Theme { model.theme }

    var body: some View {
        TileBox(theme: theme) {
            content.padding(10)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.calendar.status {
        case .notAsked:
            VStack(alignment: .leading, spacing: 3) {
                Text("Calendar access").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text)
                Button("Allow calendar access") { model.calendar.requestAccess() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.accent)
            }
        case .denied:
            Text("Calendar access denied in System Settings → Privacy & Security → Calendars")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(3)
        default:
            if let event = model.calendar.next {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Circle().fill(Color(nsColor: event.color)).frame(width: 7, height: 7)
                        Text(event.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                    }
                    Text(CalendarService.whenText(for: event))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(event.calendarName)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            } else {
                Text("No upcoming events")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }
}

// MARK: - Focus timer

struct TimerTile: View {
    @ObservedObject var model: IslandModel
    var width: CGFloat

    private var theme: Theme { model.theme }
    private var timer: FocusTimer { model.focusTimer }

    var body: some View {
        TileBox(theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(theme.track, lineWidth: 3)
                        Circle().trim(from: 0, to: timer.progress).stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "scope").font(.system(size: 15)).foregroundStyle(theme.accent)
                    }.frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Menu {
                            ForEach([15, 25, 50], id: \.self) { minutes in
                                Button("\(minutes) minutes") { timer.setMinutes(minutes) }
                                    .disabled(timer.running)
                            }
                        } label: {
                            Text(timer.remaining.mmss).font(.system(size: 22, weight: .medium))
                                .monospacedDigit().foregroundStyle(theme.text)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help("Choose session duration")
                        .accessibilityLabel("Timer duration, \(timer.remaining.mmss)")
                        Text(timer.isFinished ? "Session complete" : timer.running ? "Stay with it" : "Ready when you are")
                            .font(.system(size: 10)).foregroundStyle(theme.secondaryText).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        TileButton(symbol: timer.running ? "pause.fill" : "play.fill", tint: theme.accent) {
                            timer.running ? timer.pause() : timer.start()
                        }
                        TileButton(symbol: "arrow.counterclockwise", size: 10, tint: theme.secondaryText) { timer.reset() }
                    }
                }
                if model.settings.density == .comfortable {
                    HStack(spacing: 6) {
                        ForEach([15, 25, 50], id: \.self) { minutes in
                            Button { timer.setMinutes(minutes) } label: {
                                Text("\(minutes)m").font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .foregroundStyle(Int(timer.sessionDuration / 60) == minutes ? theme.accent : theme.secondaryText)
                                    .background(Capsule().fill(theme.control))
                            }.buttonStyle(.plain).disabled(timer.running)
                            .help("Set a \(minutes) minute session")
                        }
                    }
                }
            }.padding(10)
        }
    }

}
