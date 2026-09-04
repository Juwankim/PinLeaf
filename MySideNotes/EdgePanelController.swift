//
//  EdgePanelController.swift
//  PinLeaf
//

import AppKit
import Combine
import QuartzCore
import SwiftUI

enum ScreenEdge: String, CaseIterable, Identifiable {
    case left
    case right

    var id: Self { self }
}

struct EdgePanelConfiguration {
    var edge: ScreenEdge
    var panelWidth: CGFloat
    var preferredPanelHeight: CGFloat
    var collapsedPeekWidth: CGFloat
    var edgeTriggerWidth: CGFloat
    var animationDuration: TimeInterval
    var collapseDelay: TimeInterval

    init(
        edge: ScreenEdge = .left,
        panelWidth: CGFloat = 280,
        preferredPanelHeight: CGFloat = 640,
        collapsedPeekWidth: CGFloat = 4,
        edgeTriggerWidth: CGFloat = 3,
        animationDuration: TimeInterval = 0.24,
        collapseDelay: TimeInterval = 0.35
    ) {
        self.edge = edge
        self.panelWidth = panelWidth
        self.preferredPanelHeight = preferredPanelHeight
        self.collapsedPeekWidth = collapsedPeekWidth
        self.edgeTriggerWidth = edgeTriggerWidth
        self.animationDuration = animationDuration
        self.collapseDelay = collapseDelay
    }
}

private enum PanelSlideCurve {
    case easeIn
    case easeOut

    func value(at progress: CGFloat) -> CGFloat {
        switch self {
        case .easeIn:
            return progress * progress * progress
        case .easeOut:
            let remaining = 1 - progress
            return 1 - (remaining * remaining * remaining)
        }
    }
}

private struct PanelSlideAnimation {
    let startFrame: NSRect
    let targetFrame: NSRect
    let startTime: CFTimeInterval
    let duration: TimeInterval
    let curve: PanelSlideCurve
}

/// Owns both the note panel and a transparent hover target placed at the screen edge.
/// UI and persistence concerns intentionally do not live in this type.
@MainActor
final class EdgePanelController: NSObject, NSWindowDelegate {
    private static let initialDisplayDuration: TimeInterval = 1

    var configuration: EdgePanelConfiguration {
        didSet {
            applyConfiguration()
        }
    }

    private var notePanel: EdgeNotePanel?
    private var hoverPanel: EdgeHoverPanel?
    private let presentationState: PanelPresentationState
    private let noteStore = NoteStore()
    private lazy var floatingNotePanels = FloatingNotePanelManager(
        store: noteStore,
        panelState: presentationState
    )
    private var settingsWindowController: PanelSettingsWindowController?
    private var settingsCancellable: AnyCancellable?
    private var listLayoutCancellable: AnyCancellable?
    private var dockIconCancellable: AnyCancellable?
    private weak var targetScreen: NSScreen?
    private var hideWorkItem: DispatchWorkItem?
    private var slideTimer: Timer?
    private var slideAnimation: PanelSlideAnimation?
    private var isShown = false

    init(configuration: EdgePanelConfiguration) {
        let presentationState = PanelPresentationState(
            defaultEdge: configuration.edge,
            defaultCollapsedPeekWidth: Double(configuration.collapsedPeekWidth),
            defaultPanelWidth: Double(configuration.panelWidth)
        )
        self.presentationState = presentationState

        var resolvedConfiguration = configuration
        resolvedConfiguration.edge = presentationState.edge
        resolvedConfiguration.collapsedPeekWidth = CGFloat(
            presentationState.collapsedPeekWidth
        )
        resolvedConfiguration.panelWidth = CGFloat(presentationState.panelWidth)
        resolvedConfiguration.preferredPanelHeight = Self.preferredPanelHeight(
            displayLimit: presentationState.noteListDisplayLimit,
            rowSize: .regular
        )
        self.configuration = resolvedConfiguration
        super.init()

        settingsCancellable = Publishers.CombineLatest3(
            presentationState.$edge.removeDuplicates(),
            presentationState.$collapsedPeekWidth.removeDuplicates(),
            presentationState.$panelWidth.removeDuplicates()
        )
        .dropFirst()
        .sink { [weak self] edge, peekWidth, panelWidth in
            guard let self else { return }
            var updatedConfiguration = self.configuration
            updatedConfiguration.edge = edge
            updatedConfiguration.collapsedPeekWidth = CGFloat(peekWidth)
            updatedConfiguration.panelWidth = CGFloat(panelWidth)
            self.configuration = updatedConfiguration
        }

        listLayoutCancellable = presentationState.$noteListDisplayLimit
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] displayLimit in
                guard let self else { return }
                var updatedConfiguration = self.configuration
                updatedConfiguration.preferredPanelHeight = Self.preferredPanelHeight(
                    displayLimit: displayLimit,
                    rowSize: .regular
                )
                self.configuration = updatedConfiguration
            }

        dockIconCancellable = presentationState.$showsDockIcon
            .removeDuplicates()
            .dropFirst()
            .sink { showsDockIcon in
                let activationPolicy: NSApplication.ActivationPolicy = showsDockIcon
                    ? .regular
                    : .accessory
                NSApp.setActivationPolicy(activationPolicy)

                if showsDockIcon {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }

    func start() {
        guard notePanel == nil else { return }

        let screen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        targetScreen = screen

        notePanel = makeNotePanel(on: screen)
        hoverPanel = makeHoverPanel(on: screen)

        notePanel?.orderFrontRegardless()
        hoverPanel?.orderFrontRegardless()

        // Briefly reveal the list without making it the key window, then
        // collapse it automatically after the launch preview.
        show()
        scheduleHide(after: Self.initialDisplayDuration)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Drive the panel purely off which app is frontmost: expand while PinLeaf
        // is active, slide away the moment another app takes over. This fires
        // regardless of whether the panel ever became key.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func stop() {
        hideWorkItem?.cancel()
        stopSlideAnimation()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        noteStore.flushPendingSave()
        floatingNotePanels.closeAll()
        settingsWindowController?.closePermanently()
        settingsWindowController = nil
        notePanel?.delegate = nil
        notePanel?.close()
        hoverPanel?.close()
        notePanel = nil
        hoverPanel = nil
    }

    func show() {
        cancelScheduledHide()
        guard let panel = notePanel, let screen = targetScreen else { return }

        guard !isShown else { return }

        isShown = true
        panel.hasShadow = true
        panel.invalidateShadow()
        panel.orderFrontRegardless()
        animatePanel(to: shownFrame(on: screen), curve: .easeOut)
    }

    /// Restores the edge panel when the user clicks the app's Dock icon.
    func showAndActivate() {
        show()
        notePanel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard
            !presentationState.isPinned,
            isShown,
            notePanel != nil,
            let screen = targetScreen
        else { return }

        isShown = false
        presentationState.setPanelCollapsed(true)
        animatePanel(to: collapsedFrame(on: screen), curve: .easeIn)
    }

    /// Animates explicit window frames on the main run loop. Unlike AppKit's
    /// implicit window animator, this continues while another app is frontmost.
    private func animatePanel(to targetFrame: NSRect, curve: PanelSlideCurve) {
        guard let panel = notePanel else { return }

        stopSlideAnimation()

        let duration = max(configuration.animationDuration, 0)
        guard
            duration > 0,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            panel.frame != targetFrame
        else {
            panel.setFrame(targetFrame, display: true)
            finishSlideAnimation(for: panel)
            return
        }

        slideAnimation = PanelSlideAnimation(
            startFrame: panel.frame,
            targetFrame: targetFrame,
            startTime: CACurrentMediaTime(),
            duration: duration,
            curve: curve
        )

        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(advanceSlideAnimation(_:)),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 1.0 / 240.0
        slideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc
    private func advanceSlideAnimation(_ timer: Timer) {
        guard
            timer === slideTimer,
            let animation = slideAnimation,
            let panel = notePanel
        else {
            timer.invalidate()
            return
        }

        let elapsed = CACurrentMediaTime() - animation.startTime
        let linearProgress = CGFloat(min(max(elapsed / animation.duration, 0), 1))
        let progress = animation.curve.value(at: linearProgress)
        panel.setFrame(
            interpolatedFrame(
                from: animation.startFrame,
                to: animation.targetFrame,
                progress: progress
            ),
            display: true
        )

        guard linearProgress >= 1 else { return }
        panel.setFrame(animation.targetFrame, display: true)
        stopSlideAnimation()
        finishSlideAnimation(for: panel)
    }

    private func interpolatedFrame(
        from startFrame: NSRect,
        to targetFrame: NSRect,
        progress: CGFloat
    ) -> NSRect {
        NSRect(
            x: startFrame.origin.x
                + ((targetFrame.origin.x - startFrame.origin.x) * progress),
            y: startFrame.origin.y
                + ((targetFrame.origin.y - startFrame.origin.y) * progress),
            width: startFrame.width
                + ((targetFrame.width - startFrame.width) * progress),
            height: startFrame.height
                + ((targetFrame.height - startFrame.height) * progress)
        )
    }

    private func stopSlideAnimation() {
        slideTimer?.invalidate()
        slideTimer = nil
        slideAnimation = nil
    }

    private func finishSlideAnimation(for panel: NSWindow) {
        panel.hasShadow = isShown
        panel.invalidateShadow()
        presentationState.setPanelCollapsed(!isShown)
    }

    private func scheduleHide(after delay: TimeInterval? = nil) {
        guard !presentationState.isPinned else {
            cancelScheduledHide()
            return
        }

        hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard
                !self.isMouseInsideInteractiveArea(),
                self.notePanel?.isKeyWindow != true
            else { return }
            self.hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (delay ?? configuration.collapseDelay),
            execute: workItem
        )
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func isMouseInsideInteractiveArea() -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        let interactivePanels: [NSWindow?] = [notePanel, hoverPanel]
        return interactivePanels.contains { panel in
            guard let panel else { return false }
            return NSMouseInRect(mouseLocation, panel.frame, false)
        }
    }

    private func makeNotePanel(on screen: NSScreen) -> EdgeNotePanel {
        let panel = EdgeNotePanel(
            contentRect: collapsedFrame(on: screen),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // `start()` shows the panel right after creation, which turns the shadow on.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.minSize = NSSize(width: 1, height: 1)
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.delegate = self

        let trackingView = HoverTrackingView(frame: panel.contentRect(forFrameRect: panel.frame))
        trackingView.autoresizingMask = [.width, .height]
        trackingView.onMouseEntered = { [weak self] in
            self?.show()
        }
        trackingView.onMouseExited = { [weak self] in
            self?.scheduleHide()
        }

        let hostingView = NSHostingView(
            rootView: ContentView(
                panelState: presentationState,
                noteStore: noteStore,
                floatingPanels: floatingNotePanels,
                onOpenSettings: { [weak self] in
                    self?.showSettingsWindow()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        trackingView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: trackingView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trackingView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: trackingView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: trackingView.bottomAnchor)
        ])
        panel.contentView = trackingView

        return panel
    }

    private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = PanelSettingsWindowController(
                panelState: presentationState
            )
        }

        settingsWindowController?.show()
    }

    private func makeHoverPanel(on screen: NSScreen) -> EdgeHoverPanel {
        let panel = EdgeHoverPanel(
            contentRect: hoverFrame(on: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Keep the tiny trigger above the note panel at the physical screen edge.
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let trackingView = HoverTrackingView(frame: panel.contentRect(forFrameRect: panel.frame))
        trackingView.autoresizingMask = [.width, .height]
        trackingView.onMouseEntered = { [weak self] in
            self?.show()
        }
        trackingView.onMouseExited = { [weak self] in
            self?.scheduleHide()
        }
        panel.contentView = trackingView

        return panel
    }

    private func shownFrame(on screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let width = min(max(configuration.panelWidth, 120), visibleFrame.width)
        let height = min(
            max(configuration.preferredPanelHeight, 240),
            max(240, visibleFrame.height - 24)
        )
        let y = visibleFrame.midY - (height / 2)
        let x: CGFloat

        switch configuration.edge {
        case .left:
            x = screen.frame.minX
        case .right:
            x = screen.frame.maxX - width
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Keeps the panel at its full width while moving it beyond the screen edge.
    /// On the left edge, only the panel's rightmost `collapsedPeekWidth` points
    /// remain visible; the right edge mirrors that behavior.
    private func collapsedFrame(on screen: NSScreen) -> NSRect {
        var frame = shownFrame(on: screen)
        let visibleWidth = min(collapsedPeekWidth, frame.width)

        switch configuration.edge {
        case .left:
            frame.origin.x = screen.frame.minX - frame.width + visibleWidth
        case .right:
            frame.origin.x = screen.frame.maxX - visibleWidth
        }

        return frame
    }

    private func hoverFrame(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let x: CGFloat

        switch configuration.edge {
        case .left:
            x = screenFrame.minX
        case .right:
            x = screenFrame.maxX - configuration.edgeTriggerWidth
        }

        return NSRect(
            x: x,
            y: screenFrame.minY,
            width: configuration.edgeTriggerWidth,
            height: screenFrame.height
        )
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }

    private static func preferredPanelHeight(
        displayLimit: NoteListDisplayLimit,
        rowSize: NoteListRowSize
    ) -> CGFloat {
        let rowCount = CGFloat(displayLimit.maximumCount)
        let rowSpacing = CGFloat(max(displayLimit.maximumCount - 1, 0)) * rowSize.rowSpacing
        let chromeHeight: CGFloat = 57

        return chromeHeight
            + (rowSize.listPadding * 2)
            + (rowCount * rowSize.estimatedRowHeight)
            + rowSpacing
    }

    private var collapsedPeekWidth: CGFloat {
        min(max(configuration.collapsedPeekWidth, 1), 60)
    }

    private func applyConfiguration() {
        guard let screen = targetScreen else { return }
        stopSlideAnimation()
        hoverPanel?.setFrame(hoverFrame(on: screen), display: true)
        notePanel?.setFrame(
            isShown ? shownFrame(on: screen) : collapsedFrame(on: screen),
            display: true
        )
        notePanel?.hasShadow = isShown
        notePanel?.invalidateShadow()
        presentationState.setPanelCollapsed(!isShown)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === notePanel else { return }
        show()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === notePanel else { return }
        // Losing key inside PinLeaf (a floating note, the settings window) keeps
        // the panel out; only a switch away from the app collapses it, and that
        // is handled by `activeApplicationDidChange`.
        guard !NSApp.isActive else { return }
        hide()
    }

    /// Collapses the panel when another application becomes active. Returning to
    /// PinLeaf through a floating note must not reveal an already-hidden panel;
    /// the edge hover, the panel itself, and Dock reopen handle explicit reveals.
    @objc
    private func activeApplicationDidChange(_ notification: Notification) {
        let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        let isSelf = activatedApp?.processIdentifier == NSRunningApplication.current.processIdentifier
        guard !isSelf else { return }
        hide()
    }

    @objc
    private func screenConfigurationDidChange() {
        let screen = targetScreen.flatMap { current in
            NSScreen.screens.first { $0.frame.intersects(current.frame) }
        } ?? screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen else { return }
        targetScreen = screen
        stopSlideAnimation()
        hoverPanel?.setFrame(hoverFrame(on: screen), display: true)
        notePanel?.setFrame(
            isShown ? shownFrame(on: screen) : collapsedFrame(on: screen),
            display: true
        )
        notePanel?.hasShadow = isShown
        notePanel?.invalidateShadow()
        presentationState.setPanelCollapsed(!isShown)
    }
}

private final class EdgeNotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class EdgeHoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HoverTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    private var trackingAreaReference: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}
