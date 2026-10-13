import AppKit
import SwiftUI

/// Root view. It fills the panel; the island itself is pinned to the top-centre
/// inside a stable transparent canvas; no AppKit resize competes with layout.
struct IslandView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let size = model.size(for: model.state)
        let shape = model.shape(for: model.state)
        let _ = model.traceRender("\(model.state) size=\(Int(size.width))x\(Int(size.height))")

        ZStack(alignment: .top) {
            chrome(size: size, shape: shape)
            content(size: size)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
                .opacity(model.contentOpacity)
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    // MARK: - Icon, fill, band

    private func chrome(size: CGSize, shape: IslandShape) -> some View {
        let theme = model.theme
        let band = model.notchSize.height
        let fill = model.state.isCompactLike ? Color.black : theme.background

        return ZStack(alignment: .top) {
            // Soft shadow, masked out of the notch band so the menu bar stays clean.
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.20), radius: 14, x: 0, y: 9)
                .mask(Rectangle().padding(.top, band))

            shape.fill(fill)

            // The black band over the physical notch: the hardware cutout stays
            // black in the light theme too.
            if !model.state.isCompactLike {
                NotchBandShape(bottomRadius: IslandModel.Layout.notchCornerRadius)
                    .fill(theme.notchBandColor)
                    .frame(width: model.notchSize.width, height: band)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        switch model.state {
        case .resting:
            EmptyView()
        case .compact(let left, let right):
            compactContent(left: left, right: right, size: size)
        case .peek(let payload):
            PeekBubble(payload: payload, theme: model.theme, band: model.notchSize.height, size: size)
        case .expanded:
            tiles(size: size)
        case .appGrid:
            AppGridView(model: model, size: size)
        case .permission(let card):
            VStack(spacing: 0) {
                Spacer(minLength: 0).frame(height: model.notchSize.height + TileGrid.padding)
                TileBox(theme: model.theme, radius: 14) {
                    PermissionCardView(card: card, theme: model.theme,
                                       onAllow: { model.claude.resolve(.allow) },
                                       onDeny: { model.claude.resolve(.deny) })
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, TileGrid.padding)
            .frame(width: size.width, height: size.height, alignment: .top)
        }
    }

    private func compactContent(left: CompactSlot?, right: CompactSlot?, size: CGSize) -> some View {
        HStack(spacing: 0) {
            compactSlot(left, leading: true)
            Spacer(minLength: 0)
            compactSlot(right, leading: false)
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func compactSlot(_ slot: CompactSlot?, leading: Bool) -> some View {
        if let slot {
            slotView(slot)
                .frame(width: IslandModel.Layout.compactExtension - 4)
                .padding(leading ? .leading : .trailing, 6)
        }
    }

    @ViewBuilder
    private func slotView(_ slot: CompactSlot) -> some View {
        switch slot {
        case .symbol(let name, let accent):
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent ? model.theme.accent : model.theme.text)
        case .accentDot:
            Circle().fill(model.theme.accent).frame(width: 6, height: 6)
        case .working:
            ClaudeWorkingGrid(theme: model.theme)
        }
    }

    private func tiles(size: CGSize) -> some View {
        let rows = model.settings.rows
        let contentWidth = size.width - TileGrid.padding * 2
        let columns = max(6, TileGrid.occupiedColumns(rows))
        return VStack(spacing: 0) {
            workspaceNavigation
                .frame(height: model.notchSize.height)
            Color.clear.frame(height: TileGrid.padding)
            VStack(spacing: 0) {
                if rows.isEmpty {
                    VStack(spacing: 8) {
                        Text("Make this space yours").font(.system(size: 15, weight: .semibold))
                        Button("Choose tiles in Settings") { SettingsWindowController.shared.show(model: model) }
                            .foregroundStyle(model.theme.accent)
                    }
                    .foregroundStyle(model.theme.text)
                    .frame(height: model.settings.tileHeight)
                } else {
                    VStack(spacing: TileGrid.gap) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: TileGrid.gap) {
                                ForEach(row) { config in
                                    let width = TileGrid.fittedWidth(cells: config.cells, contentWidth: contentWidth, columns: columns)
                                    TileView(model: model, config: config, width: width)
                                        .frame(width: width, height: model.settings.tileHeight)
                                        .contextMenu {
                                            Button("Hide \(config.id.title)") { model.settings.toggle(config.id) }
                                            ForEach(1...3, id: \.self) { cells in
                                                Button("\(cells) cell\(cells == 1 ? "" : "s")") { model.settings.setCells(config.id, cells) }
                                            }
                                            Divider()
                                            Button("Customize dashboard…") { SettingsWindowController.shared.show(model: model) }
                                        }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .id(model.settings.workspace)
            .padding(.horizontal, TileGrid.padding)
            dashboardUtilities
                .padding(.horizontal, TileGrid.padding)
                .padding(.vertical, TileGrid.padding / 2)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private var workspaceNavigation: some View {
        let wingWidth = (model.navigationWidth - model.notchSize.width) / 2
        return HStack(spacing: 0) {
            workspaceWing([.everyday, .developer])
                .frame(width: wingWidth)
            Color.clear.frame(width: model.notchSize.width)
                .accessibilityHidden(true)
            workspaceWing([.media, .focus])
                .frame(width: wingWidth)
        }
        .frame(width: model.navigationWidth, height: model.notchSize.height)
    }

    private func workspaceWing(_ workspaces: [Workspace]) -> some View {
        HStack(spacing: 2) {
            ForEach(workspaces) { workspace in
                Button { model.settings.selectWorkspace(workspace) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: workspace.symbol).font(.system(size: 10))
                        Text(workspace.title).font(.system(size: 10, weight: .medium))
                            .lineLimit(1).fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .foregroundStyle(model.settings.workspace == workspace ? model.theme.accent : model.theme.secondaryText)
                    .background(RoundedRectangle(cornerRadius: 6).fill(model.settings.workspace == workspace ? model.theme.accent.opacity(0.14) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(IslandButtonStyle(theme: model.theme))
                .accessibilityLabel("\(workspace.title) dashboard")
                .accessibilityAddTraits(model.settings.workspace == workspace ? .isSelected : [])
                .help("\(workspace.title) dashboard")
            }
        }
        .padding(.horizontal, 8)
    }

    private var dashboardUtilities: some View {
        HStack(spacing: 4) {
            Button { model.showAppGrid() } label: {
                Label("Apps", systemImage: "square.grid.2x2")
                    .padding(.horizontal, 5).frame(height: 22)
            }
            .buttonStyle(IslandButtonStyle(theme: model.theme))
            Spacer(minLength: 0)
            Button { model.togglePin() } label: {
                Image(systemName: model.pinned ? "pin.fill" : "pin")
                    .frame(width: 24, height: 22)
                    .foregroundStyle(model.pinned ? model.theme.accent : model.theme.secondaryText)
            }
            .buttonStyle(IslandButtonStyle(theme: model.theme))
            .accessibilityLabel(model.pinned ? "Unpin island" : "Keep island open")
            .help(model.pinned ? "Unpin; keep open while hovering" : "Keep island open")
            Button { SettingsWindowController.shared.show(model: model) } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 24, height: 22)
            }
            .buttonStyle(IslandButtonStyle(theme: model.theme))
            .accessibilityLabel("Customize dashboard")
            .help("Customize dashboard")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(model.theme.secondaryText)
        .frame(height: IslandModel.Layout.dashboardFooter)
    }

}

// MARK: - Tile dispatch

struct TileView: View {
    @ObservedObject var model: IslandModel
    let config: TileConfig
    let width: CGFloat

    var body: some View {
        if config.cells == 1 {
            MiniTile(model: model, id: config.id)
        } else {
        switch config.id {
        case .music:
            MusicTile(model: model, width: width)
        case .weather:
            WeatherTile(model: model, width: width)
        case .messages:
            MessagesTile(model: model, width: width)
        case .controls:
            ControlsTile(model: model, width: width)
        case .calendar:
            CalendarTile(model: model, width: width)
        case .timer:
            TimerTile(model: model, width: width)
        case .developer:
            DeveloperTile(model: model, width: width)
        case .launcher:
            LauncherTile(model: model)
        }
        }
    }
}

// MARK: - Peek bubble

struct PeekBubble: View {
    let payload: PeekPayload
    let theme: Theme
    let band: CGFloat
    let size: CGSize

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0).frame(height: band)
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(payload.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    if let subtitle = payload.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(width: size.width, height: IslandModel.Layout.peekHeight)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            let tint = payload.warning ? theme.warningOrange : theme.accent
            if let image = payload.icon {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(theme.isDark ? 0.18 : 0.14))
                Image(systemName: payload.symbol ?? "bell.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 30, height: 30)
    }
}

// MARK: - Claude working indicator (15 fps, only while the pill shows it)

struct ClaudeWorkingGrid: View {
    let theme: Theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * 15) % 12
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { column in
                    VStack(spacing: 2) {
                        ForEach(0..<2, id: \.self) { row in
                            let index = column + row * 3
                            let distance = abs(index - (tick > 5 ? 11 - tick : tick))
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(theme.accent.opacity(distance == 0 ? 1 : (distance == 1 ? 0.55 : 0.25)))
                                .frame(width: 4, height: 4)
                        }
                    }
                }
            }
        }
        .frame(width: 18, height: 10)
        .transaction { $0.animation = nil }
    }
}
