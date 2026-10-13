import XCTest
@testable import Notch

final class InteractionTests: XCTestCase {
    @MainActor
    func testRapidWorkspaceChangesKeepBackingFrameAndNavigationAnchored() {
        let name = "NotchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        let model = IslandModel(startServices: false, settings: settings)
        let backing = model.presentationFrame
        let navigation = model.navigationWidth
        model.showDashboard()
        for _ in 0..<5 {
            for workspace in Workspace.allCases {
                settings.selectWorkspace(workspace)
                for density in DashboardDensity.allCases {
                    settings.density = density
                    XCTAssertEqual(model.presentationFrame, backing)
                    XCTAssertEqual(model.navigationWidth, navigation)
                    XCTAssertTrue(backing.contains(model.screenRect(for: .expanded)))
                    XCTAssertEqual(model.screenRect(for: .expanded).midX, model.geometry.centerX)
                }
            }
        }
        settings.tiles = TileID.allCases.map { TileConfig(id: $0, visible: true, cells: 3) }
        settings.layout = .board
        settings.density = .comfortable
        XCTAssertTrue(backing.contains(model.screenRect(for: .expanded)))
        let card = PermissionCard(id: "long", tool: "Bash", command: String(repeating: "command ", count: 1000), session: "test", received: Date())
        XCTAssertTrue(backing.contains(model.screenRect(for: .permission(card))))
        model.toggleExpanded()
        XCTAssertEqual(model.presentationFrame, backing)
        let outside = CGPoint(x: backing.minX + 1, y: backing.minY + 1)
        XCTAssertFalse(model.containsScreenPoint(outside), "Transparent canvas must not capture input")
    }

    @MainActor
    func testWingTabsAndFooterDoNotToggleThePin() {
        let model = IslandModel(startServices: false)
        model.showDashboard()
        let size = model.size(for: .expanded)
        let left = (size.width - model.notchSize.width) / 2
        let right = left + model.notchSize.width
        for point in [CGPoint(x: left - 40, y: 16), CGPoint(x: right + 40, y: 16),
                      CGPoint(x: size.width - 24, y: size.height - 7)] {
            XCTAssertTrue(model.isContentPoint(point, in: size))
            model.handleClick(at: point, size: size)
            XCTAssertTrue(model.pinned)
            XCTAssertEqual(model.state, .expanded)
        }
        XCTAssertFalse(model.isContentPoint(CGPoint(x: size.width / 2, y: 16), in: size))
    }

    func testCompleteBoardRowsHaveEqualOuterMargins() {
        let width: CGFloat = 520
        let tile = TileGrid.fittedWidth(cells: 3, contentWidth: width, columns: 6)
        XCTAssertEqual(tile * 2 + TileGrid.gap, width, accuracy: 0.001)
        XCTAssertEqual(tile, (width - TileGrid.gap) / 2, accuracy: 0.001)
        let small = TileGrid.fittedWidth(cells: 1, contentWidth: width, columns: 6)
        XCTAssertEqual(small * 6 + TileGrid.gap * 5, width, accuracy: 0.001)
    }

    func testRibbonFitsOnANarrowScreen() {
        let width: CGFloat = 720
        let cells = [3, 2, 3, 2]
        let total = cells.reduce(CGFloat.zero) { $0 + TileGrid.fittedWidth(cells: $1, contentWidth: width, columns: 10) }
        XCTAssertEqual(total + TileGrid.gap * 3, width, accuracy: 0.001)
    }

    func testApproachIncludesBelowNotchAndTopEdgeWithoutCoveringMenuItems() {
        let notch = CGRect(x: 500, y: 968, width: 180, height: 32)
        let closed = notch
        XCTAssertTrue(PointerRegion.contains(CGPoint(x: 590, y: 960), notch: notch, island: closed, open: false))
        XCTAssertTrue(PointerRegion.contains(CGPoint(x: 590, y: 1000), notch: notch, island: closed, open: false))
        XCTAssertFalse(PointerRegion.contains(CGPoint(x: 590, y: 950), notch: notch, island: closed, open: false))
        XCTAssertFalse(PointerRegion.contains(CGPoint(x: 470, y: 980), notch: notch, island: closed, open: false))
    }

    func testExpandedHoverToleratesSmallExitAndRejectsFarAwayPoints() {
        let notch = CGRect(x: 500, y: 968, width: 180, height: 32)
        let island = CGRect(x: 300, y: 640, width: 580, height: 360)
        XCTAssertTrue(PointerRegion.contains(CGPoint(x: 885, y: 800), notch: notch, island: island, open: true))
        XCTAssertFalse(PointerRegion.contains(CGPoint(x: 910, y: 800), notch: notch, island: island, open: true))
        XCTAssertFalse(PointerRegion.contains(CGPoint(x: 590, y: 800), notch: notch, island: notch, open: false))
    }

    @MainActor
    func testHoverDwellCancellationAndExitGrace() async throws {
        let model = IslandModel(startServices: false)
        model.pointerMoved(isInside: true)
        model.pointerMoved(isInside: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(model.state, .resting)
        model.pointerMoved(isInside: true)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(model.state, .expanded)
        model.pointerMoved(isInside: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.state, .expanded)
        model.pointerMoved(isInside: true)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(model.state, .expanded)
        model.pointerMoved(isInside: false)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(model.state, .resting)
    }

    @MainActor
    func testExplicitCloseRequiresPointerToLeaveBeforeReopening() async throws {
        let model = IslandModel(startServices: false)
        model.showDashboard()
        model.toggleExpanded()
        model.pointerMoved(isInside: true)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(model.state, .resting)
        model.pointerMoved(isInside: false)
        model.pointerMoved(isInside: true)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(model.state, .expanded)
    }

    @MainActor
    func testPermissionAndOpenDashboardAreNotInterrupted() {
        let model = IslandModel(startServices: false)
        model.showDashboard()
        model.showPeek(.info(symbol: "bolt", title: "Connected"))
        XCTAssertEqual(model.state, .expanded)
        let card = PermissionCard(id: "test", tool: "Bash", command: "swift test", session: "test", received: Date())
        model.pinPermission(card)
        model.toggleExpanded()
        model.showAppGrid()
        model.showDashboard()
        model.handleOutsideClick()
        XCTAssertEqual(model.state, .permission(card))
    }
}
