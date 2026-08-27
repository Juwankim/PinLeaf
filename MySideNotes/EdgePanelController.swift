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
    var collapsedVisibleFraction: CGFloat
    var inactiveOpacity: CGFloat
    var edgeTriggerWidth: CGFloat
    var animationDuration: TimeInterval
    var collapseDelay: TimeInterval

    init(
        edge: ScreenEdge = .left,
        panelWidth: CGFloat = 280,
        preferredPanelHeight: CGFloat = 640,
        collapsedVisibleFraction: CGFloat = 0.10,
        inactiveOpacity: CGFloat = 0.42,
        edgeTriggerWidth: CGFloat = 3,
        animationDuration: TimeInterval = 0.24,
        collapseDelay: TimeInterval = 0.35
    ) {
        self.edge = edge
        self.panelWidth = panelWidth
        self.preferredPanelHeight = preferredPanelHeight
        self.collapsedVisibleFraction = collapsedVisibleFraction
        self.inactiveOpacity = inactiveOpacity
        self.edgeTriggerWidth = edgeTriggerWidth
        self.animationDuration = animationDuration
        self.collapseDelay = collapseDelay
    }
}

/// Owns both the note panel and a transparent hover target placed at the screen edge.
/// UI and persistence concerns intentionally do not live in this type.
@MainActor
final class EdgePanelController: NSObject, NSWindowDelegate {
    var configuration: EdgePanelConfiguration {
        didSet {
            applyConfiguration()
        }
    }

    private var notePanel: EdgeNotePanel?
    private var hoverPanel: EdgeHoverPanel?
    private let presentationState: PanelPresentationState
    private let noteStore = NoteStore()
    private lazy var floatingNotePanels = FloatingNotePanelManager(store: noteStore)
    private var settingsWindowController: PanelSettingsWindowController?
    private var settingsCancellable: AnyCancellable?
    private var listLayoutCancellable: AnyCancellable?
    private var dockIconCancellable: AnyCancellable?
    private weak var targetScreen: NSScreen?
    private var hideWorkItem: DispatchWorkItem?
    private var isMouseInsidePanel = false
    private var isShown = false

    init(configuration: EdgePanelConfiguration) {
        let presentationState = PanelPresentationState(
            defaultEdge: configuration.edge,
            defaultInactiveOpacity: Double(configuration.inactiveOpacity),
            defaultCollapsedVisibleFraction: Double(configuration.collapsedVisibleFraction),
            defaultPanelWidth: Double(configuration.panelWidth)
        )
        self.presentationState = presentationState

        var resolvedConfiguration = configuration
        resolvedConfiguration.edge = presentationState.edge
        resolvedConfiguration.inactiveOpacity = CGFloat(presentationState.inactiveOpacity)
        resolvedConfiguration.collapsedVisibleFraction = CGFloat(
            presentationState.collapsedVisibleFraction
        )
        resolvedConfiguration.panelWidth = CGFloat(presentationState.panelWidth)
        resolvedConfiguration.preferredPanelHeight = Self.preferredPanelHeight(
            displayLimit: presentationState.noteListDisplayLimit,
            rowSize: .regular
        )
        self.configuration = resolvedConfiguration
        super.init()

        settingsCancellable = Publishers.CombineLatest4(
            presentationState.$edge.removeDuplicates(),
            presentationState.$inactiveOpacity.removeDuplicates(),
            presentationState.$collapsedVisibleFraction.removeDuplicates(),
            presentationState.$panelWidth.removeDuplicates()
        )
        .dropFirst()
        .sink { [weak self] edge, opacity, visibleFraction, panelWidth in
            guard let self else { return }
            var updatedConfiguration = self.configuration
            updatedConfiguration.edge = edge
            updatedConfiguration.inactiveOpacity = CGFloat(opacity)
            updatedConfiguration.collapsedVisibleFraction = CGFloat(visibleFraction)
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

        if presentationState.isPinned {
            show()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func stop() {
        hideWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
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

        if isShown {
            panel.alphaValue = 1
            return
        }

        isShown = true
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = configuration.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(shownFrame(on: screen), display: true)
            panel.animator().alphaValue = 1
        }
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
            let panel = notePanel,
            let screen = targetScreen
        else { return }

        isShown = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = configuration.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(collapsedFrame(on: screen), display: true)
            panel.animator().alphaValue = inactiveOpacity
        }
    }

    private func scheduleHide() {
        guard !presentationState.isPinned else {
            cancelScheduledHide()
            return
        }

        hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isMouseInsidePanel, self.notePanel?.isKeyWindow != true else { return }
            self.hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + configuration.collapseDelay,
            execute: workItem
        )
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
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
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.alphaValue = inactiveOpacity
        panel.delegate = self

        let trackingView = HoverTrackingView(frame: panel.contentRect(forFrameRect: panel.frame))
        trackingView.autoresizingMask = [.width, .height]
        trackingView.onMouseEntered = { [weak self] in
            self?.isMouseInsidePanel = true
            self?.show()
        }
        trackingView.onMouseExited = { [weak self] in
            self?.isMouseInsidePanel = false
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
        trackingView.onMouseEntered = { [weak self] in self?.show() }
        trackingView.onMouseExited = { [weak self] in self?.scheduleHide() }
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

    private func collapsedFrame(on screen: NSScreen) -> NSRect {
        var frame = shownFrame(on: screen)
        let visibleWidth = frame.width * collapsedVisibleFraction

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
        let chromeHeight: CGFloat = 61

        return chromeHeight
            + (rowSize.listPadding * 2)
            + (rowCount * rowSize.estimatedRowHeight)
            + rowSpacing
    }

    private var collapsedVisibleFraction: CGFloat {
        min(max(configuration.collapsedVisibleFraction, 0.05), 1)
    }

    private var inactiveOpacity: CGFloat {
        min(max(configuration.inactiveOpacity, 0.1), 1)
    }

    private func applyConfiguration() {
        guard let screen = targetScreen else { return }
        hoverPanel?.setFrame(hoverFrame(on: screen), display: true)
        notePanel?.setFrame(
            isShown ? shownFrame(on: screen) : collapsedFrame(on: screen),
            display: true
        )
        notePanel?.alphaValue = isShown ? 1 : inactiveOpacity
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === notePanel else { return }
        show()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === notePanel else { return }
        if let keyWindow = NSApp.keyWindow,
           keyWindow.parent === window || window.childWindows?.contains(keyWindow) == true {
            return
        }
        hide()
    }

    @objc
    private func screenConfigurationDidChange() {
        let screen = targetScreen.flatMap { current in
            NSScreen.screens.first { $0.frame.intersects(current.frame) }
        } ?? screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen else { return }
        targetScreen = screen
        hoverPanel?.setFrame(hoverFrame(on: screen), display: true)
        notePanel?.setFrame(
            isShown ? shownFrame(on: screen) : collapsedFrame(on: screen),
            display: true
        )
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
