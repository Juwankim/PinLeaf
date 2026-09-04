//
//  PanelPresentationState.swift
//  PinLeaf
//

import Combine
import Foundation

enum NoteListDisplayLimit: Int, CaseIterable, Identifiable {
    case seven = 7
    case fourteen = 14
    case twentyOne = 21

    var id: Self { self }

    var maximumCount: Int { rawValue }

    var settingsTitle: String {
        switch self {
        case .seven: "작게"
        case .fourteen: "보통"
        case .twentyOne: "많이"
        }
    }
}

enum NoteListRowSize: String, CaseIterable, Identifiable {
    case compact
    case regular
    case large

    var id: Self { self }
}

@MainActor
final class PanelPresentationState: ObservableObject {
    private static let pinnedDefaultsKey = "panel.isPinned"
    private static let edgeDefaultsKey = "panel.edge"
    private static let peekWidthDefaultsKey = "panel.collapsedPeekWidth"
    private static let panelWidthDefaultsKey = "panel.width"
    private static let showsDockIconDefaultsKey = "application.showsDockIcon"
    private static let noteListDisplayLimitDefaultsKey = "panel.noteList.displayLimit"
    private static let defaultNoteColorDefaultsKey = "panel.noteList.defaultColor"
    private static let colorNamesDefaultsKey = "panel.noteColor.names"
    static let maximumColorNameLength = 10

    @Published private(set) var isPinned: Bool
    @Published private(set) var edge: ScreenEdge
    /// How many points of the panel stay visible at the screen edge when collapsed.
    @Published private(set) var collapsedPeekWidth: Double
    @Published private(set) var panelWidth: Double
    @Published private(set) var showsDockIcon: Bool
    @Published private(set) var noteListDisplayLimit: NoteListDisplayLimit
    @Published private(set) var defaultNoteColor: NoteColor
    @Published private(set) var isPanelCollapsed = true
    /// User-provided names that override `NoteColor.displayName`; only holds
    /// trimmed, non-empty entries that actually differ from the built-in name.
    @Published private(set) var colorNames: [NoteColor: String]

    private let defaults: UserDefaults
    private let defaultEdge: ScreenEdge
    private let defaultCollapsedPeekWidth: Double
    private let defaultPanelWidth: Double
    private let defaultShowsDockIcon: Bool
    private let defaultNoteListDisplayLimit: NoteListDisplayLimit
    private let fallbackNoteColor: NoteColor

    init(
        defaults: UserDefaults = .standard,
        defaultEdge: ScreenEdge = .left,
        defaultCollapsedPeekWidth: Double = 4,
        defaultPanelWidth: Double = 280,
        defaultShowsDockIcon: Bool = true,
        defaultNoteListDisplayLimit: NoteListDisplayLimit = .fourteen,
        defaultNoteColor: NoteColor = .yellow
    ) {
        self.defaults = defaults
        self.defaultEdge = defaultEdge
        self.defaultCollapsedPeekWidth = defaultCollapsedPeekWidth
        self.defaultPanelWidth = defaultPanelWidth
        self.defaultShowsDockIcon = defaultShowsDockIcon
        self.defaultNoteListDisplayLimit = defaultNoteListDisplayLimit
        self.fallbackNoteColor = defaultNoteColor
        isPinned = defaults.bool(forKey: Self.pinnedDefaultsKey)
        showsDockIcon = Self.savedShowsDockIcon(
            defaults: defaults,
            defaultValue: defaultShowsDockIcon
        )

        let storedEdge = defaults.string(forKey: Self.edgeDefaultsKey)
            .flatMap(ScreenEdge.init(rawValue:))
        edge = storedEdge ?? defaultEdge

        let storedPeekWidth = defaults.object(forKey: Self.peekWidthDefaultsKey) == nil
            ? defaultCollapsedPeekWidth
            : defaults.double(forKey: Self.peekWidthDefaultsKey)
        collapsedPeekWidth = min(max(storedPeekWidth, 2), 20)

        let storedPanelWidth = defaults.object(forKey: Self.panelWidthDefaultsKey) == nil
            ? defaultPanelWidth
            : defaults.double(forKey: Self.panelWidthDefaultsKey)
        panelWidth = min(max(storedPanelWidth, 180), 350)

        let storedDisplayLimit = defaults.object(forKey: Self.noteListDisplayLimitDefaultsKey) == nil
            ? nil
            : NoteListDisplayLimit(
                rawValue: defaults.integer(forKey: Self.noteListDisplayLimitDefaultsKey)
            )
        noteListDisplayLimit = storedDisplayLimit ?? defaultNoteListDisplayLimit

        let storedNoteColor = defaults.string(forKey: Self.defaultNoteColorDefaultsKey)
            .flatMap(NoteColor.init(rawValue:))
        self.defaultNoteColor = storedNoteColor ?? defaultNoteColor

        let storedColorNames = defaults.dictionary(forKey: Self.colorNamesDefaultsKey)
            as? [String: String] ?? [:]
        colorNames = Self.sanitizedColorNames(from: storedColorNames)
    }

    private static func sanitizedColorNames(
        from rawNames: [String: String]
    ) -> [NoteColor: String] {
        var result: [NoteColor: String] = [:]
        for (rawColor, rawName) in rawNames {
            guard let color = NoteColor(rawValue: rawColor) else { continue }
            let name = String(
                rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(maximumColorNameLength)
            )
            if !name.isEmpty, name != color.displayName {
                result[color] = name
            }
        }
        return result
    }

    static func savedShowsDockIcon(
        defaults: UserDefaults = .standard,
        defaultValue: Bool = true
    ) -> Bool {
        guard defaults.object(forKey: showsDockIconDefaultsKey) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: showsDockIconDefaultsKey)
    }

    func togglePin() {
        isPinned.toggle()
        defaults.set(isPinned, forKey: Self.pinnedDefaultsKey)
    }

    func setEdge(_ edge: ScreenEdge) {
        guard self.edge != edge else { return }
        self.edge = edge
        defaults.set(edge.rawValue, forKey: Self.edgeDefaultsKey)
    }

    func setCollapsedPeekWidth(_ width: Double) {
        let clampedWidth = (min(max(width, 2), 20) * 10).rounded() / 10
        guard collapsedPeekWidth != clampedWidth else { return }
        collapsedPeekWidth = clampedWidth
        defaults.set(clampedWidth, forKey: Self.peekWidthDefaultsKey)
    }

    func setPanelWidth(_ width: Double) {
        let clampedWidth = min(max(width, 180), 350)
        guard panelWidth != clampedWidth else { return }
        panelWidth = clampedWidth
        defaults.set(clampedWidth, forKey: Self.panelWidthDefaultsKey)
    }

    func setShowsDockIcon(_ showsDockIcon: Bool) {
        guard self.showsDockIcon != showsDockIcon else { return }
        self.showsDockIcon = showsDockIcon
        defaults.set(showsDockIcon, forKey: Self.showsDockIconDefaultsKey)
    }

    func setNoteListDisplayLimit(_ limit: NoteListDisplayLimit) {
        guard noteListDisplayLimit != limit else { return }
        noteListDisplayLimit = limit
        defaults.set(limit.rawValue, forKey: Self.noteListDisplayLimitDefaultsKey)
    }

    func setDefaultNoteColor(_ color: NoteColor) {
        guard defaultNoteColor != color else { return }
        defaultNoteColor = color
        defaults.set(color.rawValue, forKey: Self.defaultNoteColorDefaultsKey)
    }

    /// Transient window state used to show the slim running indicator while the
    /// panel itself is outside the screen. This value is intentionally not saved.
    func setPanelCollapsed(_ isCollapsed: Bool) {
        guard isPanelCollapsed != isCollapsed else { return }
        isPanelCollapsed = isCollapsed
    }

    /// The name to show for a color: the user's override when set, otherwise the
    /// built-in `NoteColor.displayName`.
    func colorName(for color: NoteColor) -> String {
        colorNames[color] ?? color.displayName
    }

    func setColorName(_ name: String, for color: NoteColor) {
        let trimmed = String(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.maximumColorNameLength)
        )
        let resolved: String? = (trimmed.isEmpty || trimmed == color.displayName)
            ? nil
            : trimmed
        guard colorNames[color] != resolved else { return }
        colorNames[color] = resolved
        persistColorNames()
    }

    private func persistColorNames() {
        guard !colorNames.isEmpty else {
            defaults.removeObject(forKey: Self.colorNamesDefaultsKey)
            return
        }
        let rawNames = Dictionary(
            uniqueKeysWithValues: colorNames.map { ($0.key.rawValue, $0.value) }
        )
        defaults.set(rawNames, forKey: Self.colorNamesDefaultsKey)
    }

    func resetPanelSettings() {
        setEdge(defaultEdge)
        setCollapsedPeekWidth(defaultCollapsedPeekWidth)
        setPanelWidth(defaultPanelWidth)
        setShowsDockIcon(defaultShowsDockIcon)
        setNoteListDisplayLimit(defaultNoteListDisplayLimit)
        setDefaultNoteColor(fallbackNoteColor)
        for color in Array(colorNames.keys) {
            setColorName("", for: color)
        }
    }
}
