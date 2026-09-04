//
//  FloatingNotePanelManager.swift
//  PinLeaf
//

import AppKit
import Combine

@MainActor
final class FloatingNotePanelManager: ObservableObject {
    @Published private(set) var visibleNoteIDs: Set<Note.ID> = []
    @Published private(set) var restorableNoteIDs: Set<Note.ID> = []

    private let store: NoteStore
    private let panelState: PanelPresentationState
    private var panelControllers: [Note.ID: FloatingNotePanelController] = [:]
    private var notesCancellable: AnyCancellable?
    /// The notes the user has chosen to keep visible. A color filter only changes
    /// which of these windows are currently on-screen; `.all` shows their union.
    private var desiredVisibleNoteIDs: Set<Note.ID> = []
    private var activeColorFilter: NoteColorFilter = .all

    init(store: NoteStore, panelState: PanelPresentationState) {
        self.store = store
        self.panelState = panelState
        notesCancellable = store.$notes
            .dropFirst()
            .sink { [weak self] _ in
                self?.reconcileVisibleNotesWithActiveFilter()
            }
    }

    var hasVisibleNotes: Bool {
        !visibleNoteIDs.isEmpty
    }

    var hasRestorableNotes: Bool {
        !restorableNoteIDs.isEmpty
    }

    func isVisible(_ noteID: Note.ID) -> Bool {
        visibleNoteIDs.contains(noteID)
    }

    func addAndShowNote(color: NoteColor? = nil) {
        showNote(store.addNote(color: color))
    }

    /// Switches the color menu context while preserving each note's Show/Hide
    /// choice. The all-colors view therefore restores the union of every color.
    func applyColorFilter(_ newFilter: NoteColorFilter) {
        guard newFilter != activeColorFilter else { return }

        for noteID in visibleNoteIDs {
            panelControllers[noteID]?.hide()
        }
        visibleNoteIDs.removeAll()
        restorableNoteIDs.removeAll()

        activeColorFilter = newFilter

        let notesToShow = desiredVisibleNoteIDs.filter { noteID in
            guard let note = store.note(withID: noteID) else { return false }
            return newFilter.matches(note)
        }
        for noteID in notesToShow {
            panelController(for: noteID).show(activate: false)
            visibleNoteIDs.insert(noteID)
        }
    }

    func showNote(_ noteID: Note.ID) {
        guard store.note(withID: noteID) != nil else { return }

        let controller = panelController(for: noteID)
        restorableNoteIDs.remove(noteID)
        desiredVisibleNoteIDs.insert(noteID)
        visibleNoteIDs.insert(noteID)
        controller.show(activate: true)
    }

    func hideNote(_ noteID: Note.ID) {
        guard visibleNoteIDs.contains(noteID) else { return }
        panelControllers[noteID]?.hide()
        visibleNoteIDs.remove(noteID)
        desiredVisibleNoteIDs.remove(noteID)
    }

    func toggleNoteVisibility(_ noteID: Note.ID) {
        if isVisible(noteID) {
            hideNote(noteID)
        } else {
            showNote(noteID)
        }
    }

    func toggleAllNotesVisibility() {
        if hasRestorableNotes {
            restorePreviouslyVisibleNotes()
        } else {
            hideAllVisibleNotes()
        }
    }

    func hideAllVisibleNotes() {
        let currentlyVisible = Set(
            panelControllers.compactMap { noteID, controller in
                controller.isVisible ? noteID : nil
            }
        )
        guard !currentlyVisible.isEmpty else { return }

        restorableNoteIDs = currentlyVisible
        currentlyVisible.forEach { panelControllers[$0]?.hide() }
        visibleNoteIDs.subtract(currentlyVisible)
    }

    func restorePreviouslyVisibleNotes() {
        let noteIDsToRestore = restorableNoteIDs.filter { noteID in
            guard let note = store.note(withID: noteID) else { return false }
            return activeColorFilter.matches(note)
        }
        restorableNoteIDs.removeAll()

        for noteID in noteIDsToRestore {
            let controller = panelController(for: noteID)
            controller.show(activate: false)
            visibleNoteIDs.insert(noteID)
        }
    }

    /// Keeps floating windows aligned when an open note changes color while a
    /// specific color filter is selected.
    private func reconcileVisibleNotesWithActiveFilter() {
        desiredVisibleNoteIDs = Set(desiredVisibleNoteIDs.filter {
            store.note(withID: $0) != nil
        })
        restorableNoteIDs = Set(restorableNoteIDs.filter {
            store.note(withID: $0) != nil
        })

        let notesThatShouldBeVisible = Set(desiredVisibleNoteIDs.filter { noteID in
            guard
                !restorableNoteIDs.contains(noteID),
                let note = store.note(withID: noteID)
            else { return false }
            return activeColorFilter.matches(note)
        })

        for noteID in visibleNoteIDs.subtracting(notesThatShouldBeVisible) {
            panelControllers[noteID]?.hide()
        }
        for noteID in notesThatShouldBeVisible.subtracting(visibleNoteIDs) {
            panelController(for: noteID).show(activate: false)
        }
        visibleNoteIDs = notesThatShouldBeVisible
    }

    func deleteNote(_ noteID: Note.ID) {
        visibleNoteIDs.remove(noteID)
        restorableNoteIDs.remove(noteID)
        desiredVisibleNoteIDs.remove(noteID)
        panelControllers.removeValue(forKey: noteID)?.closePermanently()
        store.delete(noteID)
    }

    func closeAll() {
        for controller in panelControllers.values {
            controller.closePermanently()
        }
        panelControllers.removeAll()
        visibleNoteIDs.removeAll()
        restorableNoteIDs.removeAll()
        desiredVisibleNoteIDs.removeAll()
        activeColorFilter = .all
    }

    private func panelController(for noteID: Note.ID) -> FloatingNotePanelController {
        if let existingController = panelControllers[noteID] {
            return existingController
        }

        let controller = FloatingNotePanelController(
            noteID: noteID,
            store: store,
            panelState: panelState,
            initialFrame: restoredFrame(for: noteID) ?? initialFrame(),
            onDelete: { [weak self] in
                self?.deleteNote(noteID)
            }
        )
        controller.onClose = { [weak self] closedNoteID in
            self?.notePanelDidClose(closedNoteID)
        }
        controller.onFrameChange = { [weak self] changedNoteID, frame in
            self?.store.updateWindowFrame(
                NoteWindowFrame(
                    x: Double(frame.origin.x),
                    y: Double(frame.origin.y),
                    width: Double(frame.width),
                    height: Double(frame.height)
                ),
                for: changedNoteID
            )
        }
        panelControllers[noteID] = controller
        return controller
    }

    private func notePanelDidClose(_ noteID: Note.ID) {
        visibleNoteIDs.remove(noteID)
        restorableNoteIDs.remove(noteID)
        desiredVisibleNoteIDs.remove(noteID)
        panelControllers.removeValue(forKey: noteID)
    }

    private func restoredFrame(for noteID: Note.ID) -> NSRect? {
        guard let savedFrame = store.note(withID: noteID)?.windowFrame else { return nil }
        guard
            savedFrame.x.isFinite,
            savedFrame.y.isFinite,
            savedFrame.width.isFinite,
            savedFrame.height.isFinite,
            savedFrame.width >= 260,
            savedFrame.height >= 220
        else { return nil }

        let frame = NSRect(
            x: CGFloat(savedFrame.x),
            y: CGFloat(savedFrame.y),
            width: CGFloat(savedFrame.width),
            height: CGFloat(savedFrame.height)
        )
        guard NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else { return nil }
        return frame
    }

    private func initialFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first

        let size = NSSize(width: 330, height: 380)
        guard let visibleFrame = screen?.visibleFrame else {
            return NSRect(origin: .zero, size: size)
        }

        let preferredX = visibleFrame.midX - (size.width / 2)
        let preferredY = visibleFrame.midY
            - (size.height / 2)
            - (visibleFrame.height * 0.10)
        let x = min(max(preferredX, visibleFrame.minX), visibleFrame.maxX - size.width)
        let y = min(max(preferredY, visibleFrame.minY), visibleFrame.maxY - size.height)

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
