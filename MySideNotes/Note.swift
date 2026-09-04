//
//  Note.swift
//  PinLeaf
//

import Foundation

enum NoteColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case yellow
    case pink
    case blue
    case green
    case purple

    var id: Self { self }

    var displayName: String {
        switch self {
        case .yellow: "노랑"
        case .pink: "분홍"
        case .blue: "하늘"
        case .green: "연두"
        case .purple: "보라"
        }
    }
}

enum NoteDisplayMode: String, Codable, Sendable {
    case edit
    case preview
}

struct NoteWindowFrame: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct Note: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var body: String
    let createdAt: Date
    var updatedAt: Date
    var windowFrame: NoteWindowFrame?
    var zoomScale: Double?
    var color: NoteColor?
    var displayMode: NoteDisplayMode?
    /// Whether the floating window keeps itself above other windows. `nil` means
    /// the default, which is to stay on top.
    var isAlwaysOnTop: Bool?

    init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        windowFrame: NoteWindowFrame? = nil,
        zoomScale: Double? = nil,
        color: NoteColor? = nil,
        displayMode: NoteDisplayMode? = nil,
        isAlwaysOnTop: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.windowFrame = windowFrame
        self.zoomScale = zoomScale
        self.color = color
        self.displayMode = displayMode
        self.isAlwaysOnTop = isAlwaysOnTop
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        let firstBodyLine = body
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return firstBodyLine?.isEmpty == false ? firstBodyLine! : "제목 없음"
    }

    var effectiveZoomScale: Double {
        min(max(zoomScale ?? 1, 0.5), 2)
    }

    var effectiveColor: NoteColor {
        color ?? .yellow
    }

    var effectiveDisplayMode: NoteDisplayMode {
        displayMode ?? .edit
    }

    var effectiveIsAlwaysOnTop: Bool {
        isAlwaysOnTop ?? true
    }
}
