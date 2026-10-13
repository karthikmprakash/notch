import AppKit
import SwiftUI

/// The app grid that the quick-controls button opens. macOS 26 removed
/// Launchpad, so the grid lives inside the island instead.
@MainActor
final class AppGridModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        var id: String { url.path }
        var name: String
        var url: URL
        var icon: NSImage?
    }

    @Published private(set) var items: [Item] = []
    private var loaded = false

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let folders = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]
        var found: [Item] = []
        let manager = FileManager.default
        for folder in folders {
            guard let entries = try? manager.contentsOfDirectory(atPath: folder) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(entry)
                let name = entry.replacingOccurrences(of: ".app", with: "")
                guard !name.hasPrefix(".") else { continue }
                found.append(Item(name: name, url: url, icon: nil))
            }
        }
        var seen = Set<String>()
        items = found
            .filter { seen.insert($0.name).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { item in
                var copy = item
                let icon = NSWorkspace.shared.icon(forFile: item.url.path)
                icon.size = NSSize(width: 64, height: 64)
                copy.icon = icon
                return copy
            }
    }

    func launch(_ item: Item) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: item.url, configuration: configuration)
    }
}

// MARK: - App grid view

struct AppGridView: View {
    @ObservedObject var model: IslandModel
    var size: CGSize

    private var theme: Theme { model.theme }
    private var apps: AppGridModel { model.appGrid }

    private let columns = [GridItem(.adaptive(minimum: 58), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0).frame(height: model.notchSize.height + TileGrid.padding)
            HStack(spacing: 6) {
                Button {
                    model.closeAppGrid()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("Back").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(theme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text("Apps")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 2)
            .frame(height: 20)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, alignment: .center, spacing: 8) {
                    ForEach(apps.items) { item in
                        Button {
                            apps.launch(item)
                        } label: {
                            VStack(spacing: 3) {
                                Group {
                                    if let icon = item.icon {
                                        Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                                    } else {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.control)
                                    }
                                }
                                .frame(width: 34, height: 34)
                                Text(item.name)
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(theme.secondaryText)
                                    .lineLimit(1)
                                    .frame(width: 58)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(item.name)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 236)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TileGrid.padding)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

// MARK: - Claude permission card

struct PermissionCardView: View {
    let card: PermissionCard
    let theme: Theme
    let onAllow: () -> Void
    let onDeny: () -> Void

    /// Enough room for the whole command; only very long ones scroll.
    static func height(for card: PermissionCard) -> CGFloat {
        let lines = max(1, Int(ceil(Double(card.command.count) / 62.0)))
        let text = min(380.0, max(46.0, Double(lines) * 15.0 + 10.0))
        return 104 + text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text(card.headline)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(card.tool)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.accent.opacity(theme.isDark ? 0.18 : 0.14)))
            }

            // The whole command, never shortened. Scrolls only if it is longer
            // than the card; every character is always reachable.
            ScrollView(.vertical, showsIndicators: true) {
                Text(card.command)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
            }
            .frame(height: max(46, Self.height(for: card) - 104))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.control)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(action: onDeny) {
                    HStack(spacing: 5) {
                        Text("Deny").font(.system(size: 12, weight: .semibold))
                        Text("⌃⌥D").font(.system(size: 10, weight: .medium)).foregroundStyle(theme.secondaryText)
                    }
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(theme.control))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onAllow) {
                    HStack(spacing: 5) {
                        Text("Allow").font(.system(size: 12, weight: .semibold))
                        Text("⌃⌥A").font(.system(size: 10, weight: .medium)).opacity(0.8)
                    }
                    .foregroundStyle(theme.isDark ? Color(hex: 0x10131A) : .white)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule().fill(theme.accent))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
