import AppKit
import Combine
import SwiftUI

// MARK: - State

struct PeekPayload: Equatable {
    var symbol: String?
    var title: String
    var subtitle: String?
    /// Peeks about warnings use the muted warning colours, never the accent.
    var warning: Bool = false
    /// App peeks show the app icon instead of a symbol.
    var icon: NSImage?

    static func info(symbol: String, title: String, subtitle: String? = nil) -> PeekPayload {
        PeekPayload(symbol: symbol, title: title, subtitle: subtitle)
    }
}

enum CompactSlot: Equatable {
    case symbol(String, accent: Bool)
    case accentDot
    case working
}

enum IslandState: Equatable {
    /// Just the black notch, nothing added.
    case resting
    /// Black pill, exactly notch height, grown to the sides.
    case compact(left: CompactSlot?, right: CompactSlot?)
    /// Small bubble under the notch, shown for a few seconds.
    case peek(PeekPayload)
    /// Open island: the tiles.
    case expanded
    /// The app grid page.
    case appGrid
    /// Claude Code is asking for permission.
    case permission(PermissionCard)

    var isExpanded: Bool { self == .expanded }
    var isCompactLike: Bool { self == .resting || isCompact }

    var isCompact: Bool {
        if case .compact = self { return true }
        return false
    }
}

// MARK: - Model

@MainActor
final class IslandModel: ObservableObject {

    enum Layout {
        /// Used for service-level feedback, never dashboard geometry.
        static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
        /// How far the compact pill grows on each side of the notch.
        static let compactExtension: CGFloat = 24
        static let peekWidth: CGFloat = 360
        static let peekHeight: CGFloat = 64
        static let collapsedRadius: CGFloat = 11
        static let peekRadius: CGFloat = 22
        static let expandedRadius: CGFloat = 24
        /// Top corners of the open island: rounded, like the mockups, so the
        /// card is not mistaken for a shape with its sides cut off.
        static let openTopRadius: CGFloat = 18
        static let notchCornerRadius: CGFloat = 10
        static let hoverDelay: TimeInterval = 0.25
        static let collapseDelay: TimeInterval = 0.30
        static let dashboardFooter: CGFloat = 22
        /// Room kept below the island for the soft shadow.
        static let shadowPad: CGFloat = 24
        static let appGridRows: CGFloat = 3
        static let appGridRowHeight: CGFloat = 78
    }

    // MARK: Published

    @Published private(set) var state: IslandState = .resting
    @Published private(set) var pinned = false
    @Published private(set) var geometry: NotchGeometry

    // MARK: Services

    let settings: SettingsStore
    let music = MusicService()
    let lyrics = LyricsService()
    let weather = WeatherService()
    let messages = MessagesService()
    let controls = SystemControls()
    let calendar = CalendarService()
    let focusTimer = FocusTimer()
    let claude = ClaudeBridge()
    let appGrid = AppGridModel()

    private let peekCenter = PeekCenter()
    private var cancellables = Set<AnyCancellable>()

    var theme: Theme { Theme.of(settings.themeKind) }
    var notchSize: CGSize { geometry.notchSize }

    // MARK: Private

    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var stateBeforePeek: IslandState = .resting
    /// What the island shows while closed (music / Claude).
    private var backgroundState: IslandState = .resting
    private var stateBeforeGrid: IslandState = .expanded
    /// Dev-only: NOTCH_DEBUG_STATE pins the state so nothing overrides it.
    private var debugPinnedState = false
    private var hoverSuppressed = false
    private var lastHoverPresence: Bool?

    init(startServices: Bool = true, settings: SettingsStore? = nil) {
        self.settings = settings ?? SettingsStore.shared
        geometry = NotchLocator.current()
            ?? NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0],
                             isRealNotch: false,
                             notchSize: NotchLocator.fakeNotchSize)
        if startServices {
            wireServices()
            applyDebugState()
        }
    }

    // MARK: - Services wiring

    private func wireServices() {
        settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.settingsChanged() }
            }
            .store(in: &cancellables)

        music.$track
            .sink { [weak self] track in
                guard let self, let track else { return }
                self.lyrics.load(title: track.title, artist: track.artist,
                                 album: track.album, duration: track.duration)
                self.updateBackground()
            }
            .store(in: &cancellables)

        music.$status
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateBackground() }
            }
            .store(in: &cancellables)

        claude.$isWorking
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateBackground() }
            }
            .store(in: &cancellables)

        claude.$step
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateBackground() }
            }
            .store(in: &cancellables)

        claude.$card
            .sink { [weak self] card in
                Task { @MainActor in self?.applyCard(card) }
            }
            .store(in: &cancellables)

        claude.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .notify(let text):
                self.showPeek(.info(symbol: "sparkle", title: text), duration: 3)
            case .finished(let finished):
                self.showPeek(PeekPayload(symbol: "checkmark",
                                          title: "Claude finished",
                                          subtitle: "took \(Self.duration(finished.duration))"),
                              duration: 4)
            }
        }

        peekCenter.onPeek = { [weak self] payload in
            self?.showPeek(payload, duration: 3)
        }

        // The tiles read the child services through this model, so any change
        // in any of them has to re-render the island. Forwarded on the next
        // main-queue tick, after the child has actually written its new value.
        relay(music); relay(lyrics); relay(weather); relay(messages)
        relay(controls); relay(calendar); relay(focusTimer); relay(claude); relay(appGrid)

        HotKeys.shared.onToggleIsland = { [weak self] in self?.toggleExpanded() }
        focusTimer.onFinished = { [weak self] in
            self?.showPeek(.info(symbol: "timer", title: "Focus session complete", subtitle: "Take a moment before your next session."), duration: 4)
        }
        claude.start()
        peekCenter.start(settings: settings)
        syncServices()
        updateBackground()
    }

    /// Forward a child object's changes through this model.
    private func relay<T: ObservableObject>(_ object: T) {
        object.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.objectWillChange.send() }
            }
            .store(in: &cancellables)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        if total < 60 { return "\(total)s" }
        return "\(total / 60)m \(total % 60)s"
    }

    private func settingsChanged() {
        syncServices()
        updateBackground()
        // The island's size depends on the tile grid.
        if state.isExpanded || state == .appGrid {
            objectWillChange.send()
        }
    }

    private func syncServices() {
        if settings.config(.music).visible { music.start() } else { music.stop() }
        if settings.config(.weather).visible { weather.start(city: settings.city) } else { weather.stop() }
        if settings.config(.messages).visible { messages.start() } else { messages.stop() }
        if settings.config(.controls).visible { controls.start() } else { controls.stop() }
        if settings.config(.calendar).visible {
            calendar.start()
            // Calendar access is requested by the tile’s explicit action.
        } else {
            calendar.stop()
        }
        // A layout or theme change must never reset a running timer.
        if case .appGrid = state { appGrid.loadIfNeeded() }
    }

    /// Dev-only trace, written next to the geometry dump when NOTCH_DEBUG_DUMP is set.
    /// Checked once: the view body calls this on every render.
    private static let debugTracing = ProcessInfo.processInfo.environment["NOTCH_DEBUG_DUMP"] != nil

    /// Dev-only: called from the view body to prove it re-renders.
    func traceRender(_ text: String) { trace("render \(text)") }

    private func trace(_ text: String) {
        guard Self.debugTracing else { return }
        let url = AppPaths.support.appendingPathComponent("debug.log")
        let line = "[notch] \(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000).rounded()) \(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func updateBackground() {
        let musicActive = settings.config(.music).visible && music.isActive
        let claudeActive = claude.isWorking

        var left: CompactSlot?
        var right: CompactSlot?
        if claudeActive {
            left = .symbol(claude.step.symbol, accent: true)
            right = .working
        } else if musicActive {
            left = .symbol("music.note", accent: false)
            right = music.isPlaying ? .accentDot : nil
        } else if case .compact = backgroundState {
            left = nil
            right = nil
        }

        let next: IslandState = (left == nil && right == nil) ? .resting : .compact(left: left, right: right)
        backgroundState = next
        trace("updateBackground claudeWorking=\(claude.isWorking) step=\(claude.step) music=\(music.status) -> \(next)")
        if state.isCompactLike, !pinned, !debugPinnedState { setState(next) }
    }

    private func applyCard(_ card: PermissionCard?) {
        if let card {
            pinned = true
            expandWork?.cancel()
            expandWork = nil
            collapseWork?.cancel()
            collapseWork = nil
            setState(.permission(card))
        } else if case .permission = state {
            pinned = false
            setState(backgroundState)
        }
    }

    // MARK: - Geometry

    var expandedWidth: CGFloat {
        let rows = settings.rows
        return min(max(TileGrid.contentWidth(rows) + TileGrid.padding * 2, navigationWidth), geometry.frame.width - 40)
    }

    /// Navigation remains in the same position even when a ribbon is wider.
    var navigationWidth: CGFloat { max(520, notchSize.width + 340) }

    var presentationFrame: NSRect {
        let width = min(max(TileGrid.width(cells: 10) + TileGrid.padding * 2,
                            navigationWidth, 620, notchSize.width + 220), geometry.frame.width - 40)
            + Layout.shadowPad * 2
        // Two maximum-size tiles per board row. Permission cards have a bounded
        // scrolling command area; this envelope covers both at either density.
        let rows = ceil(CGFloat(TileID.allCases.count) / 2)
        let grid = rows * 112 + max(0, rows - 1) * TileGrid.gap + Layout.dashboardFooter
        let height = notchSize.height + TileGrid.padding * 2 + max(grid, 484) + Layout.shadowPad
        return NSRect(x: geometry.centerX - width / 2, y: geometry.screenTop - height,
                      width: width, height: height)
    }

    func size(for state: IslandState) -> CGSize {
        let n = notchSize
        switch state {
        case .resting:
            return n
        case .compact:
            return CGSize(width: n.width + Layout.compactExtension * 2, height: n.height)
        case .peek:
            return CGSize(width: max(Layout.peekWidth, n.width + 160), height: n.height + Layout.peekHeight)
        case .expanded:
            return CGSize(width: expandedWidth,
                          height: n.height + TileGrid.padding * 2 + settings.gridHeight + Layout.dashboardFooter)
        case .appGrid:
            let height = Layout.appGridRows * Layout.appGridRowHeight
            return CGSize(width: expandedWidth,
                          height: n.height + TileGrid.padding * 2 + 20 + height)
        case .permission(let card):
            let width = min(max(620, n.width + 220), geometry.frame.width - 40)
            return CGSize(width: width,
                          height: n.height + TileGrid.padding * 2 + PermissionCardView.height(for: card))
        }
    }

    func shape(for state: IslandState) -> IslandShape {
        let size = size(for: state)
        let n = notchSize
        switch state {
        case .resting, .compact:
            // Closed: square top corners, exactly notch height, so pill and
            // notch read as one shape.
            return IslandShape(topWidth: size.width, width: size.width,
                               topBand: n.height,
                               topRadius: 0, bottomRadius: Layout.collapsedRadius)
        case .peek:
            return IslandShape(topWidth: n.width, width: size.width,
                               topBand: n.height,
                               topRadius: Layout.openTopRadius, bottomRadius: Layout.peekRadius)
        default:
            return IslandShape(topWidth: n.width, width: size.width,
                               topBand: n.height,
                               topRadius: Layout.openTopRadius, bottomRadius: Layout.expandedRadius)
        }
    }

    func windowFrame(for state: IslandState) -> NSRect {
        let size = size(for: state)
        let height = size.height + Layout.shadowPad
        return NSRect(x: geometry.centerX - size.width / 2,
                      y: geometry.screenTop - height,
                      width: size.width,
                      height: height)
    }

    func screenRect(for state: IslandState) -> NSRect {
        let size = size(for: state)
        return NSRect(x: geometry.centerX - size.width / 2,
                      y: geometry.screenTop - size.height,
                      width: size.width,
                      height: size.height)
    }

    func viewRect(viewHeight: CGFloat) -> NSRect {
        let size = size(for: state)
        return NSRect(x: 0, y: viewHeight - size.height, width: size.width, height: size.height)
    }

    func containsScreenPoint(_ point: NSPoint) -> Bool {
        screenRect(for: state).contains(point)
    }

    var isOpen: Bool {
        switch state {
        case .expanded, .appGrid, .permission, .peek: return true
        default: return false
        }
    }

    var contentOpacity: Double {
        if case .resting = state { return 0 }
        return 1
    }

    func containsHoverPoint(_ point: NSPoint) -> Bool {
        PointerRegion.contains(point, notch: geometry.notchRect,
                               island: screenRect(for: state), open: isOpen)
    }

    /// True when a point (island-local, y from the top) is over content that
    /// handles its own clicks — tiles, app grid, or the permission card. Such a
    /// click must not toggle the "keep open" pin.
    func isContentPoint(_ point: NSPoint, in size: CGSize) -> Bool {
        switch state {
        case .resting, .compact, .peek:
            return false
        case .expanded:
            let notchLeft = (size.width - notchSize.width) / 2
            if point.y >= 0 && point.y <= notchSize.height {
                return point.x >= 0 && point.x <= size.width
                    && (point.x < notchLeft || point.x > notchLeft + notchSize.width)
            }
            let top = notchSize.height + TileGrid.padding
            let bottom = size.height
            return (point.y >= top && point.y <= bottom)
                && point.x >= TileGrid.padding && point.x <= size.width - TileGrid.padding
        case .appGrid, .permission:
            return point.y >= notchSize.height
        }
    }

    // MARK: - Geometry refresh

    func refreshGeometry() {
        guard let updated = NotchLocator.current() else { return }
        geometry = updated
    }

    // MARK: - State machine

    func setState(_ new: IslandState) {
        guard new != state else { return }
        trace("setState \(state) -> \(new)")
        // Frequent dashboard changes are atomic. Interpolating unlike layouts
        // creates clipped cards and moving targets, especially on rapid input.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state = new
            objectWillChange.send()
        }
    }

    func pointerMoved(isInside: Bool) {
        if lastHoverPresence != isInside {
            trace("pointerMoved inside=\(isInside) state=\(state)")
            lastHoverPresence = isInside
        }
        if hoverSuppressed {
            if !isInside { hoverSuppressed = false }
            else { return }
        }
        if isInside {
            collapseWork?.cancel()
            collapseWork = nil
            if !pinned, state.isCompactLike { scheduleExpand() }
        } else {
            expandWork?.cancel()
            expandWork = nil
            if !pinned, isOpen, !isProtected { scheduleCollapse() }
        }
    }

    /// The permission card never closes on its own.
    private var isProtected: Bool {
        if case .permission = state { return true }
        return false
    }

    func pointerExited() { pointerMoved(isInside: false) }

    private func scheduleExpand() {
        guard expandWork == nil, !state.isExpanded else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.expandWork = nil
            guard self.state.isCompactLike else { return }
            self.setState(.expanded)
        }
        expandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.hoverDelay, execute: work)
    }

    private func scheduleCollapse() {
        guard collapseWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            self.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.collapseDelay, execute: work)
    }

    private func collapse() {
        trace("collapse() called")
        expandWork?.cancel(); expandWork = nil
        collapseWork?.cancel(); collapseWork = nil
        guard !pinned, !isProtected else { return }
        setState(backgroundState)
    }

    /// Click on the island's chrome: the first one keeps it open, the next closes.
    func handleClick(at point: NSPoint, size: CGSize) {
        guard !isProtected else { return }
        guard !isContentPoint(point, in: size) else { return }
        if pinned {
            hoverSuppressed = true
            pinned = false
            collapse()
        } else {
            pinned = true
            expandWork?.cancel(); expandWork = nil
            if case .appGrid = state { return }
            setState(.expanded)
        }
    }

    /// Click outside while pinned.
    func handleOutsideClick() {
        guard !isProtected else { return }
        guard pinned else { return }
        pinned = false
        collapse()
    }

    /// Pin is persistence, not dismissal. Unpinning over the panel leaves the
    /// dashboard open until the pointer actually departs.
    func togglePin() {
        guard state == .expanded else { return }
        pinned.toggle()
        objectWillChange.send()
        if !pinned && !containsHoverPoint(NSEvent.mouseLocation) { scheduleCollapse() }
    }

    func showDashboard() {
        guard !isProtected else { return }
        hoverSuppressed = false
        pinned = true
        expandWork?.cancel(); expandWork = nil
        collapseWork?.cancel(); collapseWork = nil
        setState(.expanded)
    }

    func toggleExpanded() {
        guard !isProtected else { return }
        if pinned {
            hoverSuppressed = true
            pinned = false
            collapse()
        } else {
            hoverSuppressed = false
            pinned = true
            setState(.expanded)
        }
    }

    // MARK: - App grid

    func showAppGrid() {
        guard !isProtected else { return }
        appGrid.loadIfNeeded()
        pinned = true
        if case .appGrid = state { return }
        stateBeforeGrid = state.isExpanded ? .expanded : state
        setState(.appGrid)
    }

    func closeAppGrid() {
        setState(stateBeforeGrid == .appGrid ? .expanded : stateBeforeGrid)
    }

    /// Show a permission card immediately (used by the menu's test item and by
    /// the Claude bridge).
    func pinPermission(_ card: PermissionCard) {
        pinned = true
        expandWork?.cancel(); expandWork = nil
        collapseWork?.cancel(); collapseWork = nil
        setState(.permission(card))
    }

    var focusStatusText: String {
        switch peekCenter.focusStatus {
        case .authorized: return "Focus status: \(peekCenter.isFocusedNow ? "on" : "off")"
        case .denied: return "Focus status not granted (System Settings → Focus)"
        case .unknown: return "Focus status: asking…"
        }
    }

    // MARK: - Peeks

    func showPeek(_ payload: PeekPayload, duration: TimeInterval = 3) {
        // Never cover a permission card that is waiting for an answer.
        if case .permission = state { return }
        // Status peeks must not replace a dashboard the user is interacting with.
        if state == .expanded || state == .appGrid { return }
        peekWork?.cancel()
        stateBeforePeek = state.isExpanded ? .expanded : backgroundState
        setState(.peek(payload))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.peekWork = nil
            guard case .peek = self.state else { return }
            self.setState(self.pinned ? .expanded : self.stateBeforePeek)
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func dismissPeek() {
        peekWork?.cancel(); peekWork = nil
        guard case .peek = state else { return }
        setState(pinned ? .expanded : stateBeforePeek)
    }

    // MARK: - Demos / debug

    func demoPeek() {
        showPeek(.info(symbol: "checkmark", title: "Claude finished", subtitle: "took 2m 14s"), duration: 3)
    }

    func demoCompact() {
        pinned = false
        backgroundState = .compact(left: .symbol("music.note", accent: false), right: .accentDot)
        setState(backgroundState)
    }

    func demoResting() {
        pinned = false
        backgroundState = .resting
        setState(.resting)
    }

    /// Dev-only state override, plus `NOTCH_DEBUG_THEME` and `NOTCH_DEBUG_DUMP`.
    private func applyDebugState() {
        let env = ProcessInfo.processInfo.environment
        if let theme = env["NOTCH_DEBUG_THEME"], let kind = ThemeKind(rawValue: theme == "white" ? "whiteMatte" : "darkMatte") {
            settings.debugOverrideSuppressSave = true
            settings.themeKind = kind
        }
        if let raw = env["NOTCH_DEBUG_WORKSPACE"], let workspace = Workspace(rawValue: raw) { settings.selectWorkspace(workspace) }
        if let city = env["NOTCH_DEBUG_CITY"] { settings.city = city }
        if env["NOTCH_DEBUG_FETCH"] != nil {
            weather.refresh()
            messages.refresh()
        }
        guard let raw = env["NOTCH_DEBUG_STATE"] else { return }
        debugPinnedState = true
        switch raw {
        case "expanded": pinned = true; state = .expanded
        case "compact": state = .compact(left: .symbol("music.note", accent: false), right: .accentDot)
        case "peek": showPeek(.info(symbol: "bolt.fill", title: "Peek", subtitle: "3 s, then it goes away"), duration: 3)
        case "grid": appGrid.loadIfNeeded(); pinned = true; state = .appGrid
        case "permission":
            let card = PermissionCard(id: "demo", tool: "Bash",
                                      command: "rm -rf ./build && swift build -c release 2>&1 | tail -40",
                                      summary: "rebuild", session: "demo", received: Date())
            pinned = true
            state = .permission(card)
        default: break
        }
    }

    /// Dev-only: dump what the model computed. Prints it, and also writes
    /// ~/Library/Application Support/Notch/debug.log (launching through `open`
    /// discards stdout).
    func debugDump() {
        var lines: [String] = []
        let g = geometry
        lines.append("[notch] screen='\(g.screen.localizedName)' frame=\(g.frame) realNotch=\(g.isRealNotch) notch=\(g.notchSize) safeAreaTop=\(g.screen.safeAreaInsets.top)")
        lines.append("[notch] tiles: " + settings.visibleTiles.map { "\($0.id.rawValue)(\($0.cells))" }.joined(separator: " "))
        for state in [IslandState.resting, .compact(left: nil, right: nil), .peek(.info(symbol: "x", title: "x")), .expanded, .appGrid] {
            let size = self.size(for: state)
            let frame = windowFrame(for: state)
            lines.append(String(format: "[notch] %-9@ island=%.1fx%.1f window=(%.1f, %.1f, %.1f, %.1f)",
                                "\(state)", size.width, size.height, frame.minX, frame.minY, frame.width, frame.height))
        }
        lines.append("[notch] music=\(music.status) weather=\(weather.status) messages=\(messages.status) calendar=\(calendar.status) socket=\(claude.socketUp)")
        lines.append("[notch] theme=\(settings.themeKind.rawValue) city=\(settings.city) login=\(LaunchAtLogin.isEnabled)")
        let text = lines.joined(separator: "\n")
        print(text)
        fflush(stdout)
        try? text.write(to: AppPaths.support.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
    }
}
