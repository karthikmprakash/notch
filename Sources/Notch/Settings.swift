import AppKit
import SwiftUI

// MARK: - Tile identity and configuration

enum TileID: String, CaseIterable, Identifiable, Codable {
    case music, weather, messages, controls, calendar, timer, developer, launcher

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: return "Music"
        case .weather: return "Weather"
        case .messages: return "Messages"
        case .controls: return "Quick controls"
        case .calendar: return "Calendar"
        case .timer: return "Focus timer"
        case .developer: return "Claude activity"
        case .launcher: return "Quick launch"
        }
    }

    /// Default width in cells (1 cell = 60 pt, from the mockups).
    var defaultCells: Int {
        switch self {
        case .music: return 3
        case .weather: return 2
        case .messages: return 3
        case .controls: return 2
        case .calendar: return 3
        case .timer: return 2
        case .developer, .launcher: return 3
        }
    }

    var defaultVisible: Bool {
        switch self {
        case .music, .weather, .messages, .controls: return true
        case .calendar, .timer, .developer, .launcher: return false
        }
    }

    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .weather: return "cloud.sun"
        case .messages: return "message"
        case .controls: return "slider.horizontal.3"
        case .calendar: return "calendar"
        case .timer: return "timer"
        case .developer: return "terminal"
        case .launcher: return "arrow.up.forward.app"
        }
    }
}

struct TileConfig: Identifiable, Equatable, Codable {
    var id: TileID
    var visible: Bool
    var cells: Int
}

struct PeekSettings: Equatable, Codable {
    var apps: Bool = true
    var power: Bool = true
    var focus: Bool = true
}

// MARK: - The grid (measured from the mockups)

enum TileGrid {
    static let cell: CGFloat = 76
    static let gap: CGFloat = 6
    static let padding: CGFloat = 10
    static let tileHeight: CGFloat = 70
    static let maxCellsPerRow = 10

    static func width(cells: Int) -> CGFloat {
        let n = max(1, cells)
        return CGFloat(n) * cell + CGFloat(n - 1) * gap
    }

    /// Tiles flow left to right and wrap at 10 cells — the mockup row is 3+2+3+2.
    static func rows(_ tiles: [TileConfig], capacity: Int = maxCellsPerRow) -> [[TileConfig]] {
        var rows: [[TileConfig]] = []
        var current: [TileConfig] = []
        var used = 0
        for tile in tiles {
            let cells = min(max(tile.cells, 1), 3)
            if used + cells > capacity, !current.isEmpty {
                rows.append(current)
                current = []
                used = 0
            }
            current.append(tile)
            used += cells
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    static func rowWidth(_ row: [TileConfig]) -> CGFloat {
        guard !row.isEmpty else { return 0 }
        return row.reduce(0) { $0 + width(cells: $1.cells) } + CGFloat(row.count - 1) * gap
    }

    static func contentWidth(_ rows: [[TileConfig]]) -> CGFloat {
        rows.map(rowWidth).max() ?? width(cells: 3)
    }

    /// All rows share one cell pitch. A complete row reaches both content edges,
    /// including when the panel has a minimum width or is constrained by a screen.
    static func fittedWidth(cells: Int, contentWidth: CGFloat, columns: Int) -> CGFloat {
        let columnCount = max(1, columns)
        let pitch = (contentWidth + gap) / CGFloat(columnCount)
        return max(0, CGFloat(min(max(1, cells), columnCount)) * pitch - gap)
    }

    static func occupiedColumns(_ rows: [[TileConfig]]) -> Int {
        max(1, rows.map { $0.reduce(0) { $0 + $1.cells } }.max() ?? 1)
    }

    static func contentHeight(_ rows: [[TileConfig]]) -> CGFloat {
        guard !rows.isEmpty else { return tileHeight }
        return CGFloat(rows.count) * tileHeight + CGFloat(rows.count - 1) * gap
    }
}

// MARK: - Settings

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    @Published var themeKind: ThemeKind {
        didSet { if !debugOverrideSuppressSave { defaults.set(themeKind.rawValue, forKey: "theme") } }
    }
    /// Dev-only: NOTCH_DEBUG_THEME must not overwrite the saved preference.
    var debugOverrideSuppressSave = false
    @Published var city: String {
        didSet { defaults.set(city, forKey: "city") }
    }
    @Published private(set) var workspace: Workspace = .everyday
    @Published var layout: DashboardLayout = .ribbon { didSet { saveWorkspace() } }
    @Published var density: DashboardDensity = .compact { didSet { saveWorkspace() } }
    private var profiles: [String: WorkspaceConfiguration] = [:]
    private var switchingWorkspace = false

    @Published var tiles: [TileConfig] {
        didSet { saveTiles() }
    }
    @Published var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }
    /// Spotify's AppleScript API only exposes the cover as a URL, so showing
    /// artwork for Spotify needs one image request. Music.app artwork is read
    /// locally. Off means: no request, a neutral vinyl placeholder instead.
    @Published var fetchSpotifyArtwork: Bool {
        didSet { defaults.set(fetchSpotifyArtwork, forKey: "fetchSpotifyArtwork") }
    }
    @Published var peeks: PeekSettings = PeekSettings() {
        didSet { savePeeks() }
    }

    init(defaults store: UserDefaults = .standard) {
        defaults = store
        themeKind = ThemeKind(rawValue: store.string(forKey: "theme") ?? "") ?? .darkMatte
        city = store.string(forKey: "city") ?? "Lisbon"
        fetchSpotifyArtwork = store.object(forKey: "fetchSpotifyArtwork") as? Bool ?? true
        launchAtLogin = LaunchAtLogin.isEnabled

        var loaded: [TileConfig]
        if let data = store.data(forKey: "tiles"),
           let decoded = try? JSONDecoder().decode([TileConfig].self, from: data) {
            loaded = Self.normalized(decoded)
            // Any tile added in a later build gets its default config.
            for id in TileID.allCases where !loaded.contains(where: { $0.id == id }) {
                loaded.append(TileConfig(id: id, visible: id.defaultVisible, cells: id.defaultCells))
            }
        } else {
            loaded = TileID.allCases.map { TileConfig(id: $0, visible: $0.defaultVisible, cells: $0.defaultCells) }
        }
        tiles = loaded
        if let data = store.data(forKey: "workspaces"),
           let saved = try? JSONDecoder().decode([String: WorkspaceConfiguration].self, from: data) {
            profiles = saved
        }
        // Adopt the compact redesign once; later density choices stay personal.
        if !store.bool(forKey: "compactWingDesignMigrated") {
            for key in Array(profiles.keys) { profiles[key]?.density = .compact }
            if let data = try? JSONEncoder().encode(profiles) { store.set(data, forKey: "workspaces") }
            store.set(true, forKey: "compactWingDesignMigrated")
        }
        workspace = Workspace(rawValue: store.string(forKey: "workspace") ?? "") ?? .everyday
        let profile = profiles[workspace.rawValue] ?? (workspace == .everyday
            ? WorkspaceConfiguration(tiles: loaded, layout: .ribbon, density: .compact)
            : workspace.configuration)
        tiles = Self.normalized(profile.tiles)
        layout = profile.layout
        density = profile.density

        if let data = store.data(forKey: "peeks"),
           let decoded = try? JSONDecoder().decode(PeekSettings.self, from: data) {
            peeks = decoded
        } else {
            peeks = PeekSettings()
        }
    }

    var visibleTiles: [TileConfig] { tiles.filter(\.visible) }
    var rows: [[TileConfig]] { TileGrid.rows(visibleTiles, capacity: layout.capacity) }
    var tileHeight: CGFloat { density == .comfortable ? 112 : 82 }
    var gridHeight: CGFloat {
        CGFloat(max(1, rows.count)) * tileHeight + CGFloat(max(0, rows.count - 1)) * TileGrid.gap
    }

    func selectWorkspace(_ value: Workspace) {
        guard value != workspace else { return }
        saveWorkspace()
        switchingWorkspace = true
        workspace = value
        let profile = profiles[value.rawValue] ?? value.configuration
        tiles = Self.normalized(profile.tiles)
        layout = profile.layout
        density = profile.density
        switchingWorkspace = false
        defaults.set(value.rawValue, forKey: "workspace")
        saveWorkspace()
        objectWillChange.send()
    }

    private static func normalized(_ configs: [TileConfig]) -> [TileConfig] {
        var result: [TileConfig] = []
        for config in configs where !result.contains(where: { $0.id == config.id }) {
            result.append(TileConfig(id: config.id, visible: config.visible, cells: min(3, max(1, config.cells))))
        }
        for id in TileID.allCases where !result.contains(where: { $0.id == id }) {
            result.append(TileConfig(id: id, visible: false, cells: id.defaultCells))
        }
        return result
    }

    private func saveWorkspace() {
        guard !switchingWorkspace else { return }
        profiles[workspace.rawValue] = WorkspaceConfiguration(tiles: tiles, layout: layout, density: density)
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: "workspaces") }
    }

    func config(_ id: TileID) -> TileConfig {
        tiles.first(where: { $0.id == id }) ?? TileConfig(id: id, visible: id.defaultVisible, cells: id.defaultCells)
    }

    func toggle(_ id: TileID) {
        guard let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        tiles[index].visible.toggle()
    }

    func setCells(_ id: TileID, _ cells: Int) {
        guard let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        tiles[index].cells = min(max(cells, 1), 3)
    }

    func move(from source: IndexSet, to destination: Int) {
        tiles.move(fromOffsets: source, toOffset: destination)
    }

    func resetTiles() {
        let preset = workspace.configuration
        tiles = preset.tiles
        layout = preset.layout
        density = preset.density
    }

    private func saveTiles() {
        saveWorkspace()
        if workspace == .everyday, let data = try? JSONEncoder().encode(tiles) { defaults.set(data, forKey: "tiles") }
        objectWillChange.send()
    }

    private func savePeeks() {
        if let data = try? JSONEncoder().encode(peeks) { defaults.set(data, forKey: "peeks") }
    }
}

// MARK: - Launch at login

enum LaunchAtLogin {
    static var isEnabled: Bool {
        #if canImport(ServiceManagement)
        return SMAppService.mainApp.status == .enabled
        #else
        return false
        #endif
    }

    static func set(_ enabled: Bool) {
        #if canImport(ServiceManagement)
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("Notch: launch at login \(enabled ? "on" : "off") failed: \(error.localizedDescription)")
        }
        #endif
    }
}

#if canImport(ServiceManagement)
import ServiceManagement
#endif
