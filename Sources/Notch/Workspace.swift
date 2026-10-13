import SwiftUI

enum Workspace: String, CaseIterable, Identifiable, Codable {
    case everyday, developer, media, focus
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .everyday: return "square.grid.2x2"
        case .developer: return "terminal"
        case .media: return "play.rectangle"
        case .focus: return "scope"
        }
    }
    var subtitle: String {
        switch self {
        case .everyday: return "Your day, at a glance"
        case .developer: return "Keep your tools and attention close"
        case .media: return "A little room for what’s playing"
        case .focus: return "Less noise. More space to think."
        }
    }
    var configuration: WorkspaceConfiguration {
        let featured: [(TileID, Int)]
        let layout: DashboardLayout
        switch self {
        case .everyday:
            featured = [(.music, 3), (.weather, 2), (.messages, 3), (.controls, 2)]
            layout = .ribbon
        case .developer:
            featured = [(.developer, 3), (.timer, 3), (.controls, 3), (.launcher, 3)]
            layout = .board
        case .media:
            featured = [(.music, 3), (.controls, 3), (.weather, 3), (.launcher, 3)]
            layout = .board
        case .focus:
            featured = [(.timer, 3), (.calendar, 3)]
            layout = .board
        }
        var tiles = featured.map { TileConfig(id: $0.0, visible: true, cells: $0.1) }
        tiles += TileID.allCases.filter { id in !featured.contains { $0.0 == id } }
            .map { TileConfig(id: $0, visible: false, cells: $0.defaultCells) }
        return WorkspaceConfiguration(tiles: tiles, layout: layout, density: .compact)
    }
}

enum DashboardLayout: String, CaseIterable, Identifiable, Codable {
    case ribbon, board
    var id: String { rawValue }
    var title: String { self == .ribbon ? "Ribbon" : "Board" }
    var capacity: Int { self == .ribbon ? 10 : 6 }
}

enum DashboardDensity: String, CaseIterable, Identifiable, Codable {
    case compact, comfortable
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct WorkspaceConfiguration: Codable {
    var tiles: [TileConfig]
    var layout: DashboardLayout
    var density: DashboardDensity
}

/// A consistent, quiet control treatment across the island.
struct IslandButtonStyle: ButtonStyle {
    let theme: Theme
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 7).fill(theme.control.opacity(hovering || configuration.isPressed ? 1 : 0)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .onHover { hovering = $0 }
    }
}
