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
    private static let inactiveOpacityDefaultsKey = "panel.inactiveOpacity"
    private static let visibleFractionDefaultsKey = "panel.collapsedVisibleFraction"
    private static let panelWidthDefaultsKey = "panel.width"
    private static let showsDockIconDefaultsKey = "application.showsDockIcon"
    private static let noteListDisplayLimitDefaultsKey = "panel.noteList.displayLimit"

    @Published private(set) var isPinned: Bool
    @Published private(set) var edge: ScreenEdge
    @Published private(set) var inactiveOpacity: Double
    @Published private(set) var collapsedVisibleFraction: Double
    @Published private(set) var panelWidth: Double
    @Published private(set) var showsDockIcon: Bool
    @Published private(set) var noteListDisplayLimit: NoteListDisplayLimit

    private let defaults: UserDefaults
    private let defaultEdge: ScreenEdge
    private let defaultInactiveOpacity: Double
    private let defaultCollapsedVisibleFraction: Double
    private let defaultPanelWidth: Double
    private let defaultShowsDockIcon: Bool
    private let defaultNoteListDisplayLimit: NoteListDisplayLimit

    init(
        defaults: UserDefaults = .standard,
        defaultEdge: ScreenEdge = .left,
        defaultInactiveOpacity: Double = 0.42,
        defaultCollapsedVisibleFraction: Double = 0.10,
        defaultPanelWidth: Double = 280,
        defaultShowsDockIcon: Bool = true,
        defaultNoteListDisplayLimit: NoteListDisplayLimit = .fourteen
    ) {
        self.defaults = defaults
        self.defaultEdge = defaultEdge
        self.defaultInactiveOpacity = defaultInactiveOpacity
        self.defaultCollapsedVisibleFraction = defaultCollapsedVisibleFraction
        self.defaultPanelWidth = defaultPanelWidth
        self.defaultShowsDockIcon = defaultShowsDockIcon
        self.defaultNoteListDisplayLimit = defaultNoteListDisplayLimit
        isPinned = defaults.bool(forKey: Self.pinnedDefaultsKey)
        showsDockIcon = Self.savedShowsDockIcon(
            defaults: defaults,
            defaultValue: defaultShowsDockIcon
        )

        let storedEdge = defaults.string(forKey: Self.edgeDefaultsKey)
            .flatMap(ScreenEdge.init(rawValue:))
        edge = storedEdge ?? defaultEdge

        let storedOpacity = defaults.object(forKey: Self.inactiveOpacityDefaultsKey) == nil
            ? defaultInactiveOpacity
            : defaults.double(forKey: Self.inactiveOpacityDefaultsKey)
        inactiveOpacity = min(max(storedOpacity, 0.10), 0.90)

        let storedVisibleFraction = defaults.object(forKey: Self.visibleFractionDefaultsKey) == nil
            ? defaultCollapsedVisibleFraction
            : defaults.double(forKey: Self.visibleFractionDefaultsKey)
        collapsedVisibleFraction = min(max(storedVisibleFraction, 0.05), 0.30)

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

    func setInactiveOpacity(_ opacity: Double) {
        let clampedOpacity = min(max(opacity, 0.10), 0.90)
        guard inactiveOpacity != clampedOpacity else { return }
        inactiveOpacity = clampedOpacity
        defaults.set(clampedOpacity, forKey: Self.inactiveOpacityDefaultsKey)
    }

    func setCollapsedVisibleFraction(_ fraction: Double) {
        let clampedFraction = min(max(fraction, 0.05), 0.30)
        guard collapsedVisibleFraction != clampedFraction else { return }
        collapsedVisibleFraction = clampedFraction
        defaults.set(clampedFraction, forKey: Self.visibleFractionDefaultsKey)
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

    func resetPanelSettings() {
        setEdge(defaultEdge)
        setInactiveOpacity(defaultInactiveOpacity)
        setCollapsedVisibleFraction(defaultCollapsedVisibleFraction)
        setPanelWidth(defaultPanelWidth)
        setShowsDockIcon(defaultShowsDockIcon)
        setNoteListDisplayLimit(defaultNoteListDisplayLimit)
    }
}
