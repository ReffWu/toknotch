import AppKit
import Combine
import SwiftUI

/// Coordinates NotchWindowControllers across all connected displays.
///
/// Ensures every display has its own Notch panel, adapts to the display's hardware
/// (wrapping a physical notch on built-in MacBook screens, hugging the top bezel
/// on external displays), and keeps state, rings, and callbacks synchronized.
@MainActor
final class NotchCoordinator {
    private(set) var controllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private var fallbackController: NotchWindowController?
    private var cancellables = Set<AnyCancellable>()

    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var signInItems: [(title: String, action: () -> Void)] = [] {
        didSet {
            for controller in controllers.values {
                controller.signInItems = signInItems
            }
            fallbackController?.signInItems = signInItems
        }
    }

    private(set) var currentRings: [RingSnapshot] = []
    private(set) var isRefreshing: Bool = false
    private(set) var edge: NotchEdge = .right
    private(set) var visibility: NotchVisibility = .onHover

    init() {
        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .sink { [weak self] _ in
            MainActor.assumeIsolated { self?.syncScreens() }
        }
        .store(in: &cancellables)
    }

    func start() {
        syncScreens()
    }

    func stop() {
        cancellables.removeAll()
        for controller in controllers.values {
            controller.stop()
        }
        controllers.removeAll()
        fallbackController?.stop()
        fallbackController = nil
    }

    func syncScreens() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            if fallbackController == nil {
                let controller = makeController(for: nil)
                controller.show()
                fallbackController = controller
            }
            return
        }

        fallbackController?.stop()
        fallbackController = nil

        var activeIDs = Set<CGDirectDisplayID>()

        for screen in screens {
            guard let id = screen.displayID else {
                continue
            }
            activeIDs.insert(id)

            if let existing = controllers[id] {
                existing.relocate(cellCount: currentRings.count, screen: screen)
            } else {
                let controller = makeController(for: screen)
                controller.show()
                controllers[id] = controller
            }
        }

        // Clean up disconnected screens
        for (id, controller) in controllers where !activeIDs.contains(id) {
            controller.stop()
            controllers.removeValue(forKey: id)
        }
    }

    private func makeController(for screen: NSScreen?) -> NotchWindowController {
        let controller = NotchWindowController(screen: screen)
        controller.onRefresh = { [weak self] in self?.onRefresh?() }
        controller.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        controller.signInItems = signInItems
        controller.model.edge = edge
        controller.model.rings = currentRings
        controller.model.isRefreshing = isRefreshing
        controller.apply(visibility)
        return controller
    }

    func updateRings(_ rings: [RingSnapshot]) {
        currentRings = rings
        for controller in controllers.values {
            withAnimation(NotchMotion.unfold) {
                controller.model.rings = rings
            }
            controller.model.now = Date()
        }
        if let fallback = fallbackController {
            withAnimation(NotchMotion.unfold) {
                fallback.model.rings = rings
            }
            fallback.model.now = Date()
        }
    }

    func setRefreshing(_ refreshing: Bool) {
        isRefreshing = refreshing
        for controller in controllers.values {
            controller.model.isRefreshing = refreshing
        }
        fallbackController?.model.isRefreshing = refreshing
    }

    func apply(edge: NotchEdge) {
        self.edge = edge
        for controller in controllers.values {
            controller.apply(edge: edge)
        }
        fallbackController?.apply(edge: edge)
    }

    func apply(_ visibility: NotchVisibility) {
        self.visibility = visibility
        for controller in controllers.values {
            controller.apply(visibility)
        }
        fallbackController?.apply(visibility)
    }

    /// For testing and demo: present hover on the primary display
    func present(hovering index: Int) {
        let primary = controllers.values.first ?? fallbackController
        primary?.present(hovering: index)
    }
}
