import AppKit
import Combine
import SwiftUI

/// Owns the panel: geometry, frame changes, the pointer gate and clicks.
@MainActor
final class IslandController {
    private let model: IslandModel
    private let panel: IslandPanel
    private let container: IslandContainerView
    private let hosting: FirstMouseHostingView<IslandView>

    private var cancellables = Set<AnyCancellable>()
    private var pointerTimer: Timer?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    /// True while the pointer is over the island; drives `ignoresMouseEvents`.
    private var pointerInside = false

    init(model: IslandModel) {
        self.model = model
        self.container = IslandContainerView(frame: .zero)
        self.hosting = FirstMouseHostingView(rootView: IslandView(model: model))
        self.panel = IslandPanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        configurePanel()
        observeModel()
        observeScreens()
        applyFrame(force: true)
        panel.orderFrontRegardless()
        startMonitors()
        if ProcessInfo.processInfo.environment["NOTCH_DEBUG_DUMP"] != nil {
            model.debugDump()
        }
    }

    // MARK: - Setup

    private func configurePanel() {
        // NOTE: isFloatingPanel must be set *before* level — it resets the level
        // to NSFloatingWindowLevel (3), which would put the island under the
        // menu bar and behind full-screen apps.
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true

        // Above the menu bar (statusBar = 25) and below popup menus, so menus
        // still draw over us.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

        // Stays visible on every Space and over full-screen apps.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.worksWhenModal = true
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true          // opened by the pointer gate below
        panel.contentView = container

        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []               // never resize the window from SwiftUI
        container.addSubview(hosting)

        // Tracking callbacks are hints. Always use the same Cocoa screen point,
        // including during a panel resize; stale view-local events can disagree.
        container.onPointerMove = { [weak self] _ in self?.pointerCheckFromScreen() }
        container.onPointerExit = { [weak self] in self?.pointerCheckFromScreen() }

    }

    private func observeModel() {
        model.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.applyFrame()
                    self.updatePointerGate()
                }
            }
            .store(in: &cancellables)
    }

    private func observeScreens() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.refreshGeometry()
            }
        }
    }

    // MARK: - Window frame

    /// A stable transparent canvas removes the race between AppKit window
    /// resizing and SwiftUI layout. Only a display change resizes the backing
    /// window; input is still gated to the visible island, never the canvas.
    private func applyFrame(force: Bool = false) {
        let target = model.presentationFrame
        guard force || panel.frame != target else { return }
        panel.setFrame(target, display: true)
        hosting.frame = container.bounds
    }

    // MARK: - Pointer gate
    //
    // Hover is sampled without relying on input delivery to the physical notch.
    // Click capture remains restricted to the visible island. This also works
    // while another app owns the mouse event, without Accessibility permission.

    private func startMonitors() {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerCheckFromScreen() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        pointerCheckFromScreen()
        // Click outside while pinned -> unpin and close.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.model.containsScreenPoint(NSEvent.mouseLocation) {
                    self.model.handleOutsideClick()
                }
            }
        }
        // Click on the island -> keep it open / close it. Clicks that land on
        // tiles, the app grid or the permission card are left to those controls.
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let screenPoint = NSEvent.mouseLocation
            guard self.model.containsScreenPoint(screenPoint) else { return event }
            let islandRect = self.model.screenRect(for: self.model.state)
            // Island-local point, measured from the island's top edge.
            let point = NSPoint(x: screenPoint.x - islandRect.minX,
                                y: islandRect.maxY - screenPoint.y)
            self.model.handleClick(at: point, size: islandRect.size)
            return event
        }
    }

    private func pointerCheckFromScreen() {
        let point = NSEvent.mouseLocation
        setPointerGate(model.containsScreenPoint(point))
        model.pointerMoved(isInside: model.containsHoverPoint(point))
    }

    private func updatePointerGate() {
        pointerCheckFromScreen()
    }

    private func setPointerGate(_ inside: Bool) {
        guard inside != pointerInside || panel.ignoresMouseEvents == inside else { return }
        pointerInside = inside
        panel.ignoresMouseEvents = !inside
    }
}
