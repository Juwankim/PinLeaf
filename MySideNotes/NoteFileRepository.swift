//
//  NoteFileRepository.swift
//  PinLeaf
//

import Foundation

struct NoteFileRepository: Sendable {
    let fileURL: URL

    nonisolated init(fileURL: URL) {
        self.fileURL = fileURL
    }

    nonisolated static func applicationSupport() -> NoteFileRepository {
        let fileManager = FileManager.default
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
        let appDirectoryName = Bundle.main.bundleIdentifier ?? "PinLeaf"
        let appDirectoryURL = applicationSupportURL.appendingPathComponent(
            appDirectoryName,
            isDirectory: true
        )

        return NoteFileRepository(
            fileURL: appDirectoryURL.appendingPathComponent("notes.json")
        )
    }

    nonisolated func load() throws -> [Note]? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Note].self, from: data)
    }

    nonisolated func save(_ notes: [Note]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(notes)
        try data.write(to: fileURL, options: .atomic)
    }
}
