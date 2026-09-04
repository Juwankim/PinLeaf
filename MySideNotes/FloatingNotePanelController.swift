//
//  FloatingNotePanelController.swift
//  PinLeaf
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingNotePanelController: NSWindowController, NSWindowDelegate {
    private static let minimumContentSize = NSSize(width: 260, height: 220)

    let noteID: Note.ID
    var onClose: ((Note.ID) -> Void)?
    var onFrameChange: ((Note.ID, NSRect) -> Void)?

    private var appearanceCancellable: AnyCancellable?

    init(
        noteID: Note.ID,
        store: NoteStore,
        panelState: PanelPresentationState,
        initialFrame: NSRect,
        onDelete: @escaping () -> Void
    ) {
        self.noteID = noteID

        let panel = FocusableFloatingNotePanel(
            contentRect: initialFrame,
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .utilityWindow,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        // `initialFrame` is a saved window frame, not a content rectangle.
        panel.setFrame(initialFrame, display: false)
        let startsAlwaysOnTop = store.note(withID: noteID)?.effectiveIsAlwaysOnTop ?? true
        panel.isFloatingPanel = startsAlwaysOnTop
        panel.level = startsAlwaysOnTop ? .floating : .normal
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.contentResizeIncrements = NSSize(width: 1, height: 1)
        panel.tabbingMode = .disallowed
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.backgroundColor = NoteColor.yellow.appKitBackgroundColor

        let rootView = FloatingNoteView(
            noteID: noteID,
            store: store,
            panelState: panelState,
            onDelete: onDelete
        )
            .environment(\.colorScheme, .light)
        panel.contentView = NSHostingView(rootView: rootView)
        panel.nativeTitleBarHeight = max(
            0,
            panel.frame.height - panel.contentLayoutRect.height
        )

        super.init(window: panel)
        panel.delegate = self
        panel.onDeferredTitleBarPresentation = { [weak self, weak panel] in
            guard let self, let panel, panel.isKeyWindow else { return }
            self.setTitleBarAppearance(true, for: panel)
            self.setTitleBarGeometryVisible(true, for: panel)
        }
        panel.onZoomCommand = { [weak store] command in
            guard let store, let note = store.note(withID: noteID) else { return }

            let nextScale: Double
            switch command {
            case .zoomIn:
                nextScale = note.effectiveZoomScale + 0.1
            case .zoomOut:
                nextScale = note.effectiveZoomScale - 0.1
            case .reset:
                nextScale = 1
            }

            let roundedScale = (nextScale * 10).rounded() / 10
            store.updateZoomScale(roundedScale, for: noteID)
        }
        setTitleBarAppearance(false, for: panel)
        setTitleBarGeometryVisible(false, for: panel)

        appearanceCancellable = store.$notes
            .compactMap { notes in
                notes.first(where: { $0.id == noteID })
            }
            .sink { [weak panel] note in
                guard let panel else { return }
                panel.title = note.displayTitle
                panel.backgroundColor = note.effectiveColor.appKitBackgroundColor
                Self.applyAlwaysOnTop(note.effectiveIsAlwaysOnTop, to: panel)
            }
    }

    /// Keeps the window above other windows only while the note opts in. When it
    /// opts out the window drops to the normal level so other windows can cover it.
    private static func applyAlwaysOnTop(_ isAlwaysOnTop: Bool, to panel: NSPanel) {
        if panel.isFloatingPanel != isAlwaysOnTop {
            panel.isFloatingPanel = isAlwaysOnTop
        }
        let targetLevel: NSWindow.Level = isAlwaysOnTop ? .floating : .normal
        if panel.level != targetLevel {
            panel.level = targetLevel
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(activate: Bool) {
        guard let panel = window as? FocusableFloatingNotePanel else { return }

        if activate {
            setTitleBarAppearance(true, for: panel)
            setTitleBarGeometryVisible(true, for: panel)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    func closePermanently() {
        window?.delegate = nil
        close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(noteID)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard
            let panel = notification.object as? FocusableFloatingNotePanel,
            panel === window
        else { return }

        guard !panel.isDeferringTitleBarGeometryForResize else { return }
        setTitleBarAppearance(true, for: panel)

        // Let the activating mouse-down finish before changing the outer frame.
        DispatchQueue.main.async { [weak self, weak panel] in
            guard
                let self,
                let panel,
                panel.isKeyWindow,
                !panel.inLiveResize,
                !panel.isDeferringTitleBarGeometryForResize
            else { return }
            self.setTitleBarGeometryVisible(true, for: panel)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard
            let panel = notification.object as? FocusableFloatingNotePanel,
            panel === window
        else { return }

        panel.isDeferringTitleBarGeometryForResize = false
        setTitleBarAppearance(false, for: panel)
        setTitleBarGeometryVisible(false, for: panel)
    }

    func windowDidMove(_ notification: Notification) {
        notifyFrameChange()
    }

    func windowDidResize(_ notification: Notification) {
        notifyFrameChange()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard
            let panel = notification.object as? FocusableFloatingNotePanel,
            panel === window
        else { return }

        panel.isDeferringTitleBarGeometryForResize = false
        if panel.isKeyWindow {
            setTitleBarAppearance(true, for: panel)
            setTitleBarGeometryVisible(true, for: panel)
        }
        notifyFrameChange()
    }

    private func notifyFrameChange() {
        guard let panel = window as? FocusableFloatingNotePanel else { return }

        // Persist the focused/titled representation. This keeps saved frames
        // stable even when the user resizes the visually titleless panel.
        var frame = panel.frame
        if !panel.isTitleBarGeometryVisible {
            frame.size.height += panel.nativeTitleBarHeight
        }
        onFrameChange?(noteID, frame)
    }

    private func setTitleBarAppearance(
        _ isVisible: Bool,
        for panel: FocusableFloatingNotePanel
    ) {
        if isVisible {
            panel.titleVisibility = .visible
            panel.titlebarAppearsTransparent = false
            panel.titlebarSeparatorStyle = .automatic
        } else {
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.titlebarSeparatorStyle = .none
        }

        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
            panel.standardWindowButton($0)?.isHidden = !isVisible
        }
        panel.invalidateShadow()
    }

    private func setTitleBarGeometryVisible(
        _ isVisible: Bool,
        for panel: FocusableFloatingNotePanel
    ) {
        guard panel.isTitleBarGeometryVisible != isVisible else {
            updateMinimumSize(for: panel)
            return
        }

        let titleBarHeight = panel.nativeTitleBarHeight
        var targetFrame = panel.frame

        panel.isTitleBarGeometryVisible = isVisible
        if isVisible {
            targetFrame.size.height += titleBarHeight
            panel.contentView?.additionalSafeAreaInsets = .init()
            panel.setFrame(targetFrame, display: true)
        } else {
            // Lower the minimum before shrinking an active panel that is already
            // at its minimum titled height.
            updateMinimumSize(for: panel)
            panel.contentView?.additionalSafeAreaInsets = NSEdgeInsets(
                top: -titleBarHeight,
                left: 0,
                bottom: 0,
                right: 0
            )
            targetFrame.size.height = max(
                Self.minimumContentSize.height,
                targetFrame.height - titleBarHeight
            )
            panel.setFrame(targetFrame, display: true)
        }

        updateMinimumSize(for: panel)
        panel.contentView?.needsLayout = true
    }

    private func updateMinimumSize(for panel: FocusableFloatingNotePanel) {
        panel.contentMinSize = NSSize(
            width: Self.minimumContentSize.width,
            height: Self.minimumContentSize.height
                + (panel.isTitleBarGeometryVisible ? panel.nativeTitleBarHeight : 0)
        )
        panel.contentResizeIncrements = NSSize(width: 1, height: 1)
        panel.isMovable = true
    }
}

private enum FloatingNotePanelCommand {
    case zoomIn
    case zoomOut
    case reset
}

private final class FocusableFloatingNotePanel: NSPanel {
    var onDeferredTitleBarPresentation: (() -> Void)?
    var onZoomCommand: ((FloatingNotePanelCommand) -> Void)?
    var nativeTitleBarHeight: CGFloat = 0
    var isTitleBarGeometryVisible = true
    var isDeferringTitleBarGeometryForResize = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if
            event.type == .leftMouseDown,
            !isTitleBarGeometryVisible,
            isInResizeRegion(event.locationInWindow)
        {
            isDeferringTitleBarGeometryForResize = true
            DispatchQueue.main.async { [weak self] in
                guard
                    let self,
                    self.isDeferringTitleBarGeometryForResize,
                    !self.inLiveResize,
                    NSEvent.pressedMouseButtons & 1 == 0
                else { return }

                self.isDeferringTitleBarGeometryForResize = false
                self.onDeferredTitleBarPresentation?()
            }
        }

        let completesDeferredPresentation = event.type == .leftMouseUp
            && isDeferringTitleBarGeometryForResize

        if handleLineNavigation(event) {
            return
        }

        super.sendEvent(event)

        if completesDeferredPresentation && !inLiveResize {
            isDeferringTitleBarGeometryForResize = false
            onDeferredTitleBarPresentation?()
        }
    }

    private func isInResizeRegion(_ point: NSPoint) -> Bool {
        let bounds = NSRect(origin: .zero, size: frame.size)
        guard bounds.contains(point) else { return false }

        let resizeMargin: CGFloat = 8
        return point.x <= resizeMargin
            || point.x >= bounds.maxX - resizeMargin
            || point.y <= resizeMargin
            || point.y >= bounds.maxY - resizeMargin
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard
            event.type == .keyDown,
            modifiers.contains(.command),
            !modifiers.contains(.control),
            !modifiers.contains(.option)
        else {
            return super.performKeyEquivalent(with: event)
        }

        let command: FloatingNotePanelCommand?
        switch event.keyCode {
        case 24, 69: // Equal/plus and keypad plus
            command = .zoomIn
        case 27, 78: // Minus and keypad minus
            command = .zoomOut
        case 29, 82: // Zero and keypad zero
            command = .reset
        default:
            command = nil
        }

        guard let command else {
            return super.performKeyEquivalent(with: event)
        }

        onZoomCommand?(command)
        return true
    }

    private func handleLineNavigation(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard
            !modifiers.contains(.command),
            !modifiers.contains(.control),
            !modifiers.contains(.option),
            let textView = firstResponder as? NSTextView,
            textView.window === self,
            !textView.isFieldEditor
        else {
            return false
        }

        let modifiesSelection = modifiers.contains(.shift)
        switch event.keyCode {
        case 115: // Home
            if modifiesSelection {
                textView.moveToBeginningOfLineAndModifySelection(nil)
            } else {
                textView.moveToBeginningOfLine(nil)
            }
        case 119: // End
            if modifiesSelection {
                textView.moveToEndOfLineAndModifySelection(nil)
            } else {
                textView.moveToEndOfLine(nil)
            }
        default:
            return false
        }

        return true
    }
}
