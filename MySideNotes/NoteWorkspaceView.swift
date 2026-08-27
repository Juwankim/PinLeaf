//
//  NoteWorkspaceView.swift
//  PinLeaf
//

import SwiftUI

struct NoteWorkspaceView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var panelState: PanelPresentationState
    @ObservedObject var floatingPanels: FloatingNotePanelManager
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            NoteListToolbar(
                panelState: panelState,
                floatingPanels: floatingPanels,
                onOpenSettings: onOpenSettings,
                onQuit: onQuit
            )

            Divider()

            if store.notes.isEmpty {
                emptyState
            } else {
                noteList
            }
        }
        .background(Color(red: 0.965, green: 0.955, blue: 0.905))
    }

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: noteListRowSize.rowSpacing) {
                ForEach(displayedNotes) { note in
                    NoteListRow(
                        note: note,
                        isVisible: floatingPanels.isVisible(note.id),
                        rowSize: noteListRowSize,
                        onOpen: { floatingPanels.showNote(note.id) },
                        onToggleVisibility: {
                            floatingPanels.toggleNoteVisibility(note.id)
                        },
                        onDelete: { floatingPanels.deleteNote(note.id) }
                    )
                }
            }
            .padding(noteListRowSize.listPadding)
        }
    }

    private var noteListRowSize: NoteListRowSize { .regular }

    private var displayedNotes: [Note] {
        Array(store.notes.prefix(panelState.noteListDisplayLimit.maximumCount))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("노트 없음", systemImage: "note.text.badge.plus")
        } description: {
            Text("추가 버튼으로 플로팅 노트를 만들어 보세요.")
        } actions: {
            Button("노트 추가", action: floatingPanels.addAndShowNote)
        }
    }
}

private struct NoteListToolbar: View {
    @ObservedObject var panelState: PanelPresentationState
    @ObservedObject var floatingPanels: FloatingNotePanelManager
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.red)
            }
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityLabel("PinLeaf 종료")
            .help("PinLeaf 종료 (⌘Q)")

            Spacer()

            Button(action: floatingPanels.addAndShowNote) {
                Image(systemName: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel("노트 추가")
            .help("새 노트")

            Button(action: floatingPanels.toggleAllNotesVisibility) {
                Image(systemName: floatingPanels.hasRestorableNotes ? "eye" : "eye.slash")
            }
            .disabled(!floatingPanels.hasRestorableNotes && !floatingPanels.hasVisibleNotes)
            .accessibilityLabel(
                floatingPanels.hasRestorableNotes ? "노트 모두 표시" : "노트 모두 숨기기"
            )
            .help(
                floatingPanels.hasRestorableNotes
                    ? "이전에 열려 있던 노트를 원래 위치에 표시합니다."
                    : "현재 열려 있는 노트를 모두 숨깁니다."
            )

            Button(action: panelState.togglePin) {
                Image(systemName: panelState.isPinned ? "pin.fill" : "pin")
            }
            .foregroundStyle(panelState.isPinned ? Color.accentColor : Color.secondary)
            .help(panelState.isPinned ? "패널 고정 해제" : "패널 고정")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .help("패널 설정")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 17, weight: .medium))
        .controlSize(.regular)
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Color.white.opacity(0.52))
    }
}

private struct NoteListRow: View {
    let note: Note
    let isVisible: Bool
    let rowSize: NoteListRowSize
    let onOpen: () -> Void
    let onToggleVisibility: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onToggleVisibility) {
            HStack(spacing: rowSize.contentSpacing) {
                VStack(alignment: .leading, spacing: rowSize.detailSpacing) {
                    Text(note.displayTitle)
                        .font(rowSize.titleFont.weight(.medium))
                        .lineLimit(rowSize.titleLineLimit)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if rowSize.showsModifiedDate {
                        Text(note.updatedAt, format: .dateTime.month().day().hour().minute())
                            .font(rowSize.detailFont)
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .font(.system(size: rowSize.visibilityIconSize, weight: .medium))
                    .foregroundStyle(isVisible ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, rowSize.horizontalPadding)
            .padding(.vertical, rowSize.verticalPadding)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: rowSize.cornerRadius, style: .continuous)
                    .fill(
                        isVisible
                            ? note.effectiveColor.backgroundColor.opacity(0.96)
                            : note.effectiveColor.mutedListBackgroundColor
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: rowSize.cornerRadius, style: .continuous)
                    .stroke(
                        isVisible ? Color.accentColor.opacity(0.48) : Color.black.opacity(0.05)
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.displayTitle)
        .accessibilityHint(isVisible ? "이 노트를 숨깁니다." : "이 노트를 표시합니다.")
        .help(isVisible ? "클릭하여 이 노트 숨기기" : "클릭하여 이 노트 표시")
        .contextMenu {
            Button("열기", action: onOpen)

            Divider()

            Button("삭제", role: .destructive, action: onDelete)
        }
    }
}

extension NoteListRowSize {
    var listPadding: CGFloat {
        switch self {
        case .compact: 8
        case .regular: 10
        case .large: 12
        }
    }

    var rowSpacing: CGFloat {
        switch self {
        case .compact: 4
        case .regular: 6
        case .large: 8
        }
    }

    var contentSpacing: CGFloat {
        switch self {
        case .compact: 7
        case .regular: 10
        case .large: 12
        }
    }

    var detailSpacing: CGFloat {
        switch self {
        case .compact, .regular: 0
        case .large: 4
        }
    }

    var titleFont: Font {
        switch self {
        case .compact: .callout
        case .regular: .body
        case .large: .title3
        }
    }

    var detailFont: Font {
        .caption
    }

    var titleLineLimit: Int {
        self == .large ? 2 : 1
    }

    var showsModifiedDate: Bool {
        self == .large
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: 8
        case .regular: 11
        case .large: 14
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact: 5
        case .regular: 7
        case .large: 9
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: 8
        case .regular: 10
        case .large: 12
        }
    }

    var visibilityIconSize: CGFloat {
        switch self {
        case .compact: 13
        case .regular: 15
        case .large: 17
        }
    }

    var estimatedRowHeight: CGFloat {
        switch self {
        case .compact: 27
        case .regular: 33
        case .large: 58
        }
    }
}
