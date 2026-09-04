//
//  NoteStore.swift
//  PinLeaf
//

import Combine
import Foundation

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note]

    let storageURL: URL

    private let repository: NoteFileRepository
    private let saveQueue = DispatchQueue(label: "SSG.PinLeaf.note-save", qos: .utility)
    private var saveTask: Task<Void, Never>?

    init(notes: [Note]? = nil, repository: NoteFileRepository? = nil) {
        let resolvedRepository = repository ?? NoteFileRepository.applicationSupport()
        self.repository = resolvedRepository
        storageURL = resolvedRepository.fileURL

        if let notes {
            self.notes = notes
            return
        }

        do {
            if let savedNotes = try resolvedRepository.load() {
                self.notes = savedNotes
            } else {
                let welcomeNote = Self.makeWelcomeNote()
                self.notes = [welcomeNote]
                try resolvedRepository.save([welcomeNote])
            }
        } catch {
            self.notes = [Self.makeWelcomeNote()]
            NSLog("PinLeaf could not load notes.json: %@", error.localizedDescription)
        }
    }

    func note(withID id: Note.ID) -> Note? {
        notes.first { $0.id == id }
    }

    @discardableResult
    func addNote(color: NoteColor? = nil) -> Note.ID {
        let note = Note(title: "새 노트", color: color, displayMode: .edit)
        notes.insert(note, at: 0)
        scheduleSave()
        return note.id
    }

    func updateTitle(_ title: String, for id: Note.ID) {
        update(id) { note in
            note.title = title
        }
    }

    func updateBody(_ body: String, for id: Note.ID) {
        update(id) { note in
            note.body = body
        }
    }

    func updateWindowFrame(_ frame: NoteWindowFrame, for id: Note.ID) {
        update(id, touchUpdatedAt: false) { note in
            note.windowFrame = frame
        }
    }

    func updateZoomScale(_ scale: Double, for id: Note.ID) {
        update(id, touchUpdatedAt: false) { note in
            note.zoomScale = min(max(scale, 0.5), 2)
        }
    }

    func updateColor(_ color: NoteColor, for id: Note.ID) {
        update(id, touchUpdatedAt: false) { note in
            note.color = color
        }
    }

    func updateDisplayMode(_ displayMode: NoteDisplayMode, for id: Note.ID) {
        update(id, touchUpdatedAt: false) { note in
            note.displayMode = displayMode
        }
    }

    func updateAlwaysOnTop(_ isAlwaysOnTop: Bool, for id: Note.ID) {
        update(id, touchUpdatedAt: false) { note in
            note.isAlwaysOnTop = isAlwaysOnTop
        }
    }

    func delete(_ id: Note.ID) {
        guard let deletedIndex = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: deletedIndex)
        scheduleSave()
    }

    /// Ensures the newest snapshot reaches disk before application termination.
    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil

        let repository = repository
        let snapshot = notes
        do {
            try saveQueue.sync {
                try repository.save(snapshot)
            }
        } catch {
            NSLog("PinLeaf could not flush notes.json: %@", error.localizedDescription)
        }
    }

    private func update(
        _ id: Note.ID,
        touchUpdatedAt: Bool = true,
        mutation: (inout Note) -> Void
    ) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        var note = notes[index]
        mutation(&note)
        if touchUpdatedAt {
            note.updatedAt = .now
        }
        notes[index] = note
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()

        let repository = repository
        let saveQueue = saveQueue
        let snapshot = notes
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            saveQueue.async {
                do {
                    try repository.save(snapshot)
                } catch {
                    NSLog("PinLeaf could not save notes.json: %@", error.localizedDescription)
                }
            }
        }
    }

    private static func makeWelcomeNote() -> Note {
        Note(
            title: "새 노트",
            body: "# PinLeaf – Sticky Notes\n\n여기에 일반 텍스트 또는 **Markdown**을 입력하세요."
        )
    }
}
