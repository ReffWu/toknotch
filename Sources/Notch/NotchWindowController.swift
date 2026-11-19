import AppKit
import SwiftUI
import Combine

@MainActor
final class NotchWindowController {
    let model = NotchViewModel()

    /// The panel's content view, so a test can check what SwiftUI is and is not
    /// allowed to reach.
    var panelContentViewForTesting: NSView? { panel?.contentView }

    /// What AppKit settled on, for tests that need to see the panel move and
    /// fade rather than take our word for it.
    var panelFrameForTesting: CGRect? { panel?.frame }
    var panelAlphaForTesting: CGFloat { panel?.alphaValue ?? 0 }

    /// Hooked up by the app delegate; drives the menu's "Refresh now".
    var onRefresh: (() -> Void)?
    /// One "Sign in to …" item per provider that needs a browser session.
    var signInItems: [(title: String, action: () -> Void)] = []
    /// Refetch a single provider, asked for by clicking its ring.
    /// Open the settings window, asked for by clicking the handle.
    var onOpenSettings: (() -> Void)?

    private var panel: NotchPanel?
    private var hostingView: NotchHostingView<NotchRootView>?
    private var cancellables = Set<AnyCancellable>()
    private var mouseMonitors: [Any] = []
    private var systemObservers: [NSObjectProtocol] = []
    private var clearHoverWork: DispatchWorkItem?
    private var clockTimer: Timer?
    private var cursorTimer: Timer?
    /// Set by `stop()`, and final. A stopped controller must never put a panel
    /// back up: one that did would have nothing following the pointer, and a
    /// notch nobody is tracking is a notch that never folds.
    private var isStopped = false
    /// When hovering last opened the notch.
    private var openedAt: Date?
    /// A click this soon after the notch opened under the pointer was aimed at
    /// whatever was there a moment before, not at the notch.
    private static let pinSettle: TimeInterval = 0.35

    private(set) var targetScreen: NSScreen?
    private(set) var displayID: CGDirectDisplayID?

    init(screen: NSScreen? = nil) {
        self.targetScreen = screen
        self.displayID = screen?.displayID
    }

    func currentScreen() -> NSScreen? {
        if let displayID, let matched = NSScreen.screens.first(where: { $0.displayID == displayID }) {
            return matched
        }
        return targetScreen ?? NotchGeometry.preferredScreen(from: NSScreen.screens)
    }

    /// Hover in is quick; hover out waits, because the pointer has to cross the
    /// gap between the notch and the card without the card vanishing under it.
    private let hoverGrace: TimeInterval = 0.25
    /// Longer than the hover grace: folding shut is a bigger movement than
    /// dismissing a tooltip, and doing it the instant the pointer strays feels
    /// twitchy rather than responsive.
    private let foldGrace: TimeInterval = 0.45
    private var foldWork: DispatchWorkItem?
    /// Whether we have pushed the pointing hand onto the cursor stack.
    private var isPointing = false
    /// The usable area the panel was last placed against.
    ///
    /// The notch is pinned to `visibleFrame` so it rests on the Dock rather than
    /// under it — but an auto-hiding Dock revealing or concealing itself fires
    /// no screen-parameter notification, so nothing would tell us the space had
    /// come back. The cursor poll is already running; noticing there costs one
    /// rect comparison every 0.3s and needs no new machinery.
    private var lastVisibleFrame: CGRect?

    func show() {
        relocate()
        startWatchingCursor()
        startWatchingSystem()
        startClock()

        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .sink { [weak self] _ in
            MainActor.assumeIsolated { self?.relocate() }
        }
        .store(in: &cancellables)

        // On the next turn: `@Published` fires in `willSet`, so answering here
        // would be answering for the card that is just going away.
        model.$hoveredIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMouseAcceptance() }
            }
            .store(in: &cancellables)

        // The notch is as tall as the ring list, so gaining or losing one has to
        // resize the panel, not just redraw inside it.
        model.$rings
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self] count in
                // The count comes from the emission, not from re-reading the
                // model: `@Published` fires in `willSet`, so `model.rings`
                // is still the previous array at this point.
                MainActor.assumeIsolated { self?.relocate(cellCount: count) }
            }
            .store(in: &cancellables)
    }

    /// For screenshots: open, with one card showing, and no longer following
    /// the pointer, which would otherwise fold it again within a moment.
    func present(hovering index: Int) {
        cursorTimer?.invalidate()
        cursorTimer = nil
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        model.isAlwaysOn = true
        model.isExpanded = true
        model.hoveredIndex = index
        updateMouseAcceptance()
    }

    func stop() {
        isStopped = true
        setPointing(false)
        foldWork?.cancel()
        foldWork = nil
        clearHoverWork?.cancel()
        clearHoverWork = nil
        edgeChange += 1   // a crossing still in flight must not land
        cursorTimer?.invalidate()
        cursorTimer = nil
        clockTimer?.invalidate()
        clockTimer = nil
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        let workspace = NSWorkspace.shared.notificationCenter
        systemObservers.forEach(workspace.removeObserver)
        systemObservers.removeAll()
        cancellables.removeAll()
        panel?.close()
        panel = nil
        hostingView = nil
    }

    // MARK: - Placement

    func relocate(cellCount: Int? = nil, screen: NSScreen? = nil) {
        guard !isStopped else { return }
        if let screen {
            self.targetScreen = screen
            self.displayID = screen.displayID
        }
        guard let screen = currentScreen() else { return }
        model.adopt(screen: screen)
        let size = model.panelSize(cellCount: cellCount ?? model.rings.count)
        let frame = NotchGeometry.panelFrame(for: screen, panelSize: size, edge: model.edge)
        lastVisibleFrame = screen.visibleFrame

        if let panel {
            panel.setFrame(frame, display: true)
        } else {
            let panel = NotchPanel(contentRect: frame)
            let hosting = NotchHostingView(rootView: NotchRootView(model: model))
            // The panel's size is ours alone (see below), so SwiftUI is given
            // no constraints to argue with it through either.
            hosting.sizingOptions = []
            hosting.isInteractive = { [weak self] in self?.isInteractive($0) ?? false }
            panel.contextMenuProvider = { [weak self] in self?.contextMenu() }
            panel.onClick = { [weak self] in self?.handleClick() }

            // The hosting view goes *inside* a plain container rather than
            // being the content view itself.
            //
            // As the content view, SwiftUI gets a say in the window's frame: it
            // reports the content's ideal size, and this view's root is a
            // `GeometryReader`, whose ideal size is 10x10. On the side edges
            // that never surfaced. Turned horizontal, AppKit started walking
            // the window down toward it — 522pt of height to 266, to 10, to
            // zero — until nothing was drawn at all and the constraint pass
            // gave up and threw, taking the app with it.
            //
            // A container removes the channel instead of arguing with it. The
            // panel's size comes from `NotchGeometry` and from nowhere else,
            // which is what every hit region in this file already assumes.
            let container = NotchContainerView(frame: CGRect(origin: .zero, size: frame.size))
            container.autoresizingMask = [.width, .height]
            hosting.frame = container.bounds
            hosting.autoresizingMask = [.width, .height]
            container.addSubview(hosting)
            panel.contentView = container
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
            self.panel = panel
            self.hostingView = hosting
        }
        // The frame AppKit actually gave us, which is what the flush right-hand
        // edge depends on.
        if let panel {
            Log.usage.debug("panel \(NSStringFromRect(panel.frame), privacy: .public) on screen \(NSStringFromRect(screen.frame), privacy: .public)")
        }
        updateMouseAcceptance()
    }

    // MARK: - Hit regions

    /// The panel's real size, which AppKit may have rounded up from the one we
    /// asked for — and which the flush edge depends on.
    private var placement: NotchPlacement {
        NotchPlacement(edge: model.edge, panelSize: panel?.frame.size ?? model.panelSize)
    }

    /// The notch itself, in panel coordinates with a top-left origin.
    private var notchRect: CGRect { model.notchRect(in: placement) }

    /// Whether the pointer is on the settings handle — its circles, not a box
    /// around them.
    private func isOverHandle(_ local: CGPoint) -> Bool {
        model.isOverHandle(local, in: placement)
    }

    /// Whether a point is on the notch itself. See `NotchViewModel.isLive`.
    private func isLive(_ local: CGPoint) -> Bool { model.isLive(local, in: placement) }

    /// Whether a point takes the mouse: the notch, or the card it is showing.
    private func isInteractive(_ local: CGPoint) -> Bool {
        if isLive(local) { return true }
        guard model.isExpanded, let index = model.hoveredIndex,
              let card = tooltipRect(index: index) else { return false }
        return card.contains(local)
    }

    /// The pointer, wherever it is, in this panel's coordinates.
    private var pointer: CGPoint? {
        panel.map { localCursor(in: $0.frame) }
    }

    /// For tests: whether the real pointer is on this notch right now, so a
    /// test that depends on it being elsewhere can tell when it is not.
    var isPointerOnNotchForTesting: Bool { pointer.map(isInteractive) ?? false }

    /// The card, its tail, and the gap between the tail and the notch — so
    /// sliding the pointer off the notch and onto the card never leaves it.
    private func tooltipRect(index: Int) -> CGRect? {
        guard model.rings.indices.contains(index) else { return nil }
        let ring = model.rings[index]
        let cardHeight = ring.cardHeight(showingModels: model.modelLimit(for: ring))
        // Across the stack the region is the card, its tail, and the gap the
        // pointer has to cross. Along it, the card's own extent.
        let cardAcross = model.edge.isVertical ? NotchLayout.cardWidth : cardHeight
        let cardAlong = model.edge.isVertical ? cardHeight : NotchLayout.cardWidth
        let centre = model.slack + model.ringCenter(index: index)
        return placement.rect(
            along: centre - cardAlong / 2,
            across: model.contentInset + NotchLayout.bodyDepth(for: model.edge),
            length: cardAlong,
            depth: NotchLayout.tailGap + NotchLayout.tailLength + cardAcross
        )
    }

    /// Takes the mouse only while the pointer is on something. The hosting view
    /// asks `isInteractive` itself, live, so there is nothing to hand it here.
    private func updateMouseAcceptance() {
        guard let panel else { return }
        panel.ignoresMouseEvents = !isInteractive(localCursor(in: panel.frame))
    }

    // MARK: - Cursor tracking

    /// A global monitor catches the outside-to-inside crossing while the panel
    /// is still ignoring events; a local one catches the way back out.
    ///
    /// A slow poll backs both of them up, because a cursor that never moves
    /// produces no events at all — so a notch that appears, resizes or is
    /// re-anchored underneath a parked pointer would otherwise sit there with
    /// stale hover state until the user jogged the mouse.
    private func startWatchingCursor() {
        let poll = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // Only on the poll, not on every mouse-moved event: this reads
                // the screen list, and doing that per event would be work at
                // 60Hz to answer a question that changes twice a minute.
                self?.followUsableAreaIfItMoved()
                self?.cursorMoved()
            }
        }
        RunLoop.main.add(poll, forMode: .common)
        cursorTimer = poll

        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.cursorMoved() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: handler) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { event in
            handler(event)
            return event
        }) {
            mouseMonitors.append(local)
        }

        // A click anywhere else lets go of a pin, the way a click outside
        // closes any popover on the Mac. Without this a pin was released only
        // by clicking the open notch again in a spot that is neither a ring,
        // the card nor the handle — a target nobody can be expected to find,
        // so a pin made by accident was, as far as anyone could tell, forever.
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedElsewhere() }
        }) {
            mouseMonitors.append(global)
        }
        // Our own other windows — Settings, the menu bar panel, another
        // display's notch — are "elsewhere" too. This panel's own clicks are
        // `handleClick`'s.
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel { self.clickedElsewhere() }
            }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    /// Moments when the pointer's relation to the notch can change with no
    /// event to say so — a Space sliding in underneath it, the display waking,
    /// the session coming back — are asked about straight away rather than
    /// left for the next mouse movement. Going to sleep or to the login window
    /// lets go of a pin: nobody comes back expecting a notch they held open
    /// before lunch to still be in the way.
    private func startWatchingSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let recheck: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in recheck {
            systemObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.cursorMoved() }
            })
        }
        let away: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        for name in away {
            systemObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.releasePin() }
            })
        }
    }

    /// A click that did not land on this notch or its card.
    private func clickedElsewhere() {
        guard model.isPinned, let pointer, !isInteractive(pointer) else { return }
        releasePin()
    }

    /// Lets go of a pin made by hand and folds, as hovering would once the
    /// pointer is away. Settings' Always show is not a pin and is untouched.
    private func releasePin() {
        guard model.isPinned else { return }
        model.isPinned = false
        cursorMoved()
    }

    private func localCursor(in frame: CGRect) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
    }

    /// Has the Dock appeared, gone away, moved or resized since we last placed
    /// the panel? Nothing notifies us, so this is asked rather than told.
    private func followUsableAreaIfItMoved() {
        guard let screen = currentScreen() else { return }
        guard screen.visibleFrame != lastVisibleFrame else { return }
        relocate()
    }

    private func cursorMoved() {
        guard let panel else { return }
        let local = localCursor(in: panel.frame)
        setExpanded(isInteractive(local))

        var target: Int?
        if model.isExpanded, notchRect.contains(local) {
            target = cellIndex(along: placement.along(of: local))
        } else if model.isExpanded, let current = model.hoveredIndex,
                  let card = tooltipRect(index: current),
                  card.contains(local) {
            target = current
        }

        let overHandle = model.isExpanded && isOverHandle(local)
        if model.isHoveringSettings != overHandle {
            model.isHoveringSettings = overHandle
        }
        setPointing(
            Self.wantsPointingHand(isExpanded: model.isExpanded, cellIndex: target) || overHandle
        )

        if let target {
            clearHoverWork?.cancel()
            clearHoverWork = nil
            if model.hoveredIndex != target {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                    model.hoveredIndex = target
                }
            }
        } else if model.hoveredIndex != nil, clearHoverWork == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.clearHoverWork = nil
                    withAnimation(.easeOut(duration: 0.18)) { self.model.hoveredIndex = nil }
                }
            }
            clearHoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverGrace, execute: work)
        }

        updateMouseAcceptance()
    }

    /// Opens on contact, folds shut after a pause — unless it has been pinned
    /// open, in which case the pointer is not what decides.
    private func setExpanded(_ wanted: Bool) {
        if wanted {
            foldWork?.cancel()
            foldWork = nil
            guard !model.isExpanded else { return }
            openedAt = Date()
            withAnimation(NotchMotion.unfold) { model.isExpanded = true }
            Telemetry.recordActivity()
            return
        }

        guard model.isExpanded, !model.staysOpen, foldWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.foldWork = nil
                guard !self.model.staysOpen else { return }
                // Asked again rather than trusted: the pointer may have come
                // back in the grace period without an event to say so.
                if let pointer = self.pointer, self.isInteractive(pointer) { return }
                withAnimation(NotchMotion.unfold) {
                    self.model.isExpanded = false
                    self.model.hoveredIndex = nil
                }
                self.setPointing(false)
                self.updateMouseAcceptance()
            }
        }
        foldWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + foldGrace, execute: work)
    }

    /// The rings are buttons, so they should say so.
    static func wantsPointingHand(isExpanded: Bool, cellIndex: Int?) -> Bool {
        isExpanded && cellIndex != nil
    }

    /// Pushed and popped rather than `set`, so leaving restores whatever cursor
    /// the app underneath had chosen. Setting `.arrow` on the way out would
    /// stamp an arrow over someone else's text caret.
    private func setPointing(_ wanted: Bool) {
        guard wanted != isPointing else { return }
        isPointing = wanted
        if wanted {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }

    /// A click on a ring refetches that provider; a click anywhere else on the
    /// open notch pins it. The ring is the more specific target, so it wins.
    func handleClick() {
        guard let panel, model.isExpanded else {
            // Opens it, the same as the pointer arriving would — it must not
            // also pin it. The pill's hot zone is deliberately generous, since
            // it is a small target on a screen edge, so a click aimed at
            // something else nearby can land here without the notch ever
            // having been seen open. Pinning is what a click on a notch that
            // is *already* open does; folding it back in later is exactly
            // the ordinary hover behaviour, which a plain `setExpanded` leaves
            // intact.
            setExpanded(true)
            return
        }
        let local = localCursor(in: panel.frame)

        // The handle sits inside the notch, so it has to be tested before the
        // cells — otherwise the cell band nearest the foot of the stack swallows
        // it and clicking the gear refetches a provider instead.
        if isOverHandle(local) {
            onOpenSettings?()
            return
        }
        // On the card: open it out, or close it again.
        if let index = model.hoveredIndex,
           tooltipRect(index: index)?.contains(local) == true {
            model.toggleExpansion()
            return
        }
        // Only the bar itself is a target from here on. A click beside the
        // handle's circles, or anywhere else the panel happens to be taking the
        // mouse, is not a request for anything.
        guard notchRect.contains(local) else { return }
        if let index = cellIndex(along: placement.along(of: local)),
           model.rings.indices.contains(index) {
            // Every ring is a view of the same local read, so clicking any of
            // them asks for that read again rather than for one ring's share.
            onRefresh?()
            return
        }
        // Hover opens the notch the instant the pointer arrives, so a click
        // aimed at whatever was under it a moment ago lands on an open notch.
        // That is the case the folded-notch guard above was written for, and
        // it never reached it.
        if let openedAt, Date().timeIntervalSince(openedAt) < Self.pinSettle { return }
        togglePinned()
    }

    /// Move the notch to another screen edge.
    ///
    /// It goes out where it was, crosses while there is nothing to see, and
    /// then **opens** where it now is — the same unfold hovering uses, so a
    /// move ends the way reaching for it does rather than with a bar appearing
    /// at full size.
    ///
    /// Changing the placement moves the panel, turns the shape on its side and
    /// relays the whole stack, all in one frame. Done in view that is a jump no
    /// animation can smooth over, and animating a panel across a corner looks
    /// like a bug rather than a choice — hence the crossing rather than a
    /// slide.
    func apply(edge: NotchEdge) {
        // Against where the notch is *going*, not where it still is: going
        // right → top → right inside one crossing otherwise read the second
        // right as "already there", skipped it, and let the top move land —
        // leaving the notch on an edge Settings no longer said.
        guard (pendingEdge ?? model.edge) != edge else { return }
        guard let panel else {   // before there is anything on screen to fade
            model.edge = edge
            relocate()
            return
        }

        let wasOpen = model.isExpanded || pendingWasOpen
        pendingWasOpen = wasOpen
        pendingEdge = edge
        model.hoveredIndex = nil
        setPointing(false)

        // Clicking through the picker starts a move before the last one has
        // landed, and a stale completion would drop the notch on an edge the
        // user has already moved on from.
        edgeChange += 1
        let change = edgeChange

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.edgeCrossfade
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, change == self.edgeChange else { return }

                // Land folded, and at full strength: the opening *is* the
                // animation, and fading in underneath it would be two at once.
                self.pendingEdge = nil
                self.pendingWasOpen = false
                self.model.edge = edge
                self.model.isExpanded = false
                self.relocate()
                self.updateMouseAcceptance()
                panel.alphaValue = 1

                guard wasOpen else { return }
                // A beat, then open. Not decoration: setting it shut and open
                // again inside one turn lets SwiftUI coalesce the pair, and the
                // notch arrives at full size having animated nothing.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.arrivalBeat) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, change == self.edgeChange else { return }
                        withAnimation(NotchMotion.unfold) { self.model.isExpanded = true }
                        self.updateMouseAcceptance()
                    }
                }
            }
        }
    }

    /// Half the crossing, each way. Short: it is a settings change, not a
    /// flourish, and the notch should be back before you have looked up.
    private static let edgeCrossfade: TimeInterval = 0.16
    /// The pause between landing and opening.
    private static let arrivalBeat: TimeInterval = 0.05
    private var edgeChange = 0
    /// The edge a crossing in flight is heading for, and whether the notch
    /// was open when the first of a run of crossings began.
    private var pendingEdge: NotchEdge?
    private var pendingWasOpen = false

    func apply(_ visibility: NotchVisibility) {
        switch visibility {
        case .alwaysShow:
            panel?.orderFrontRegardless()
            model.isAlwaysOn = true
            // Any pin made by hand is subsumed by the setting; leaving it set
            // would outlive a later switch back to hover.
            model.isPinned = false
            foldWork?.cancel()
            foldWork = nil
            withAnimation(NotchMotion.unfold) { model.isExpanded = true }
        case .onHover:
            panel?.orderFrontRegardless()
            model.isAlwaysOn = false
            model.isPinned = false
            // Fold now rather than waiting for the pointer to leave: it may
            // already be somewhere else, in which case nothing would arrive to
            // close it and "on hover" would look exactly like "always show".
            withAnimation(NotchMotion.unfold) {
                model.isExpanded = false
                model.hoveredIndex = nil
            }
        }
        setPointing(false)
        updateMouseAcceptance()
    }

    /// Clicking the open notch pins it, so it stays put while you read it.
    ///
    /// A no-op while Settings says Always show: there the notch is already
    /// held open by a standing choice, and letting a click release it meant
    /// the setting said one thing and the notch did another.
    func togglePinned() {
        guard !model.isAlwaysOn else { return }
        model.isPinned.toggle()
        if model.isPinned {
            foldWork?.cancel()
            foldWork = nil
            withAnimation(NotchMotion.unfold) { model.isExpanded = true }
        }
        updateMouseAcceptance()
    }

    private func cellIndex(along: CGFloat) -> Int? {
        let pitch = NotchLayout.cellPitch(for: model.edge)
        for index in model.rings.indices {
            let centre = model.slack + model.ringCenter(index: index)
            if abs(along - centre) <= pitch / 2 { return index }
        }
        return nil
    }

    // MARK: - Odds and ends

    private func startClock() {
        // Keeps "Resets in N min" from going stale while the tooltip is open.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.now = Date() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func contextMenu() -> NSMenu {
        Log.usage.debug("context menu opened")
        let menu = NSMenu()
        // AppKit otherwise decides enablement itself and overrules the line
        // below. Turning it off means every item has to say so for itself.
        menu.autoenablesItems = false
        let keepOpen = NSMenuItem(
            title: "Keep open",
            action: #selector(MenuActions.togglePinned(_:)),
            keyEquivalent: ""
        )
        keepOpen.target = menuActions
        // Checked whichever way it is being held open, but only changeable
        // when it is the click that is holding it — the setting is Settings'
        // to change, and a menu item that silently loses is worse than one
        // that says it is not yours to press.
        keepOpen.state = model.staysOpen ? .on : .off
        keepOpen.isEnabled = !model.isAlwaysOn
        keepOpen.toolTip = model.isAlwaysOn
            ? "TokNotch is set to Always show. Change it in Settings."
            : nil
        menu.addItem(keepOpen)
        menu.addItem(.separator())

        let refresh = NSMenuItem(
            title: "Refresh now",
            action: #selector(MenuActions.refreshNow(_:)),
            keyEquivalent: "r"
        )
        refresh.target = menuActions
        refresh.isEnabled = true
        menu.addItem(refresh)

        for (index, entry) in signInItems.enumerated() {
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(MenuActions.signIn(_:)),
                keyEquivalent: ""
            )
            item.target = menuActions
            item.tag = index
            item.isEnabled = true
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit TokNotch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ).isEnabled = true
        return menu
    }

    private lazy var menuActions = MenuActions(
        refresh: { [weak self] in self?.onRefresh?() },
        signIn: { [weak self] index in self?.signInItems[safe: index]?.action() },
        togglePinned: { [weak self] in self?.togglePinned() }
    )
}


/// A menu item needs an Objective-C target, which a `@MainActor` Swift class
/// with closures cannot be directly.
final class MenuActions: NSObject {
    private let refresh: () -> Void
    private let signIn: (Int) -> Void
    private let pin: () -> Void

    init(
        refresh: @escaping () -> Void,
        signIn: @escaping (Int) -> Void,
        togglePinned: @escaping () -> Void
    ) {
        self.refresh = refresh
        self.signIn = signIn
        self.pin = togglePinned
    }

    @objc func refreshNow(_ sender: Any?) { refresh() }
    @objc func togglePinned(_ sender: Any?) { pin() }

    @objc func signIn(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        signIn(item.tag)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
