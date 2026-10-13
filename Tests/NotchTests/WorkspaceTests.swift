import XCTest
@testable import Notch

final class WorkspaceTests: XCTestCase {
    @MainActor
    func testCompactMigrationPreservesCompositionAndLaterDensityChoice() throws {
        let name = "NotchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var profile = Workspace.media.configuration
        profile.density = .comfortable
        profile.tiles[0].cells = 2
        defaults.set("media", forKey: "workspace")
        defaults.set(try JSONEncoder().encode(["media": profile]), forKey: "workspaces")
        let migrated = SettingsStore(defaults: defaults)
        XCTAssertEqual(migrated.density, .compact)
        XCTAssertEqual(migrated.config(.music).cells, 2)
        migrated.density = .comfortable
        XCTAssertEqual(SettingsStore(defaults: defaults).density, .comfortable)
    }

    @MainActor
    func testWorkspaceEditsStayIndependentAndSurviveReload() {
        let name = "NotchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.setCells(.music, 1)
        settings.selectWorkspace(.developer)
        XCTAssertTrue(settings.config(.developer).visible)
        XCTAssertFalse(settings.config(.weather).visible)
        settings.setCells(.developer, 2)
        settings.layout = .ribbon
        settings.density = .compact
        settings.selectWorkspace(.everyday)
        XCTAssertEqual(settings.config(.music).cells, 1)
        settings.selectWorkspace(.developer)
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.workspace, .developer)
        XCTAssertEqual(reloaded.config(.developer).cells, 2)
        XCTAssertEqual(reloaded.layout, .ribbon)
        XCTAssertEqual(reloaded.density, .compact)
        reloaded.resetTiles()
        XCTAssertEqual(reloaded.config(.developer).cells, 3)
        XCTAssertEqual(reloaded.layout, .board)
        reloaded.selectWorkspace(.everyday)
        XCTAssertEqual(reloaded.config(.music).cells, 1)
    }

    @MainActor
    func testLegacyLayoutKeepsOrderAndClampsInvalidSizes() throws {
        let name = "NotchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let old = [TileConfig(id: .controls, visible: true, cells: 99),
                   TileConfig(id: .music, visible: false, cells: 0)]
        defaults.set(try JSONEncoder().encode(old), forKey: "tiles")
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.tiles.first?.id, .controls)
        XCTAssertEqual(settings.config(.controls).cells, 3)
        XCTAssertEqual(settings.config(.music).cells, 1)
        XCTAssertEqual(Set(settings.tiles.map(\.id)).count, TileID.allCases.count)
    }

    func testPresetRowsFitTheirCapacity() {
        for workspace in Workspace.allCases {
            let profile = workspace.configuration
            let rows = TileGrid.rows(profile.tiles.filter(\.visible), capacity: profile.layout.capacity)
            XCTAssertFalse(rows.isEmpty)
            for row in rows { XCTAssertLessThanOrEqual(row.reduce(0) { $0 + $1.cells }, profile.layout.capacity) }
        }
        XCTAssertEqual(TileGrid.rows(Workspace.developer.configuration.tiles.filter(\.visible), capacity: 6).count, 2)
    }

    @MainActor
    func testTimerKeepsItsSelectedDurationAfterPauseAndReset() {
        let timer = FocusTimer()
        timer.setMinutes(50)
        timer.start()
        XCTAssertTrue(timer.running)
        timer.pause()
        XCTAssertFalse(timer.running)
        XCTAssertGreaterThan(timer.remaining, 2990)
        timer.reset()
        XCTAssertEqual(timer.remaining, 3000)
        XCTAssertEqual(timer.progress, 0)
    }
}
