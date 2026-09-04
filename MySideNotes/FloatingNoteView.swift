//
//  FloatingNoteView.swift
//  PinLeaf
//

import SwiftUI

struct FloatingNoteView: View {
    private static let compactTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    let noteID: Note.ID
    @ObservedObject var store: NoteStore
    @ObservedObject var panelState: PanelPresentationState
    let onDelete: () -> Void
    @State private var bodyDraft: String
    @State private var bodySelection: TextSelection?
    @State private var isDeleteConfirmationPresented = false
    @FocusState private var focusedField: FocusedField?

    init(
        noteID: Note.ID,
        store: NoteStore,
        panelState: PanelPresentationState,
        onDelete: @escaping () -> Void
    ) {
        self.noteID = noteID
        self.store = store
        self.panelState = panelState
        self.onDelete = onDelete
        _bodyDraft = State(initialValue: store.note(withID: noteID)?.body ?? "")
    }

    var body: some View {
        Group {
            if let note = store.note(withID: noteID) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        TextField("제목", text: titleBinding)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .semibold))
                            .focused($focusedField, equals: .title)
                            .onSubmit {
                                focusBodyAtBeginning()
                            }
                            .onKeyPress(.tab) {
                                focusBodyAtBeginning()
                                return .handled
                            }

                        Spacer(minLength: 4)

                        HStack(spacing: 6) {
                            HStack(spacing: 2) {
                                displayModeButton(
                                    .edit,
                                    systemImage: "pencil.circle",
                                    label: "편집 모드"
                                )
                                displayModeButton(
                                    .preview,
                                    systemImage: "eye.circle",
                                    label: "읽기 모드"
                                )
                            }
                            .padding(2)
                            .background(Color.black.opacity(0.055), in: Capsule())

                            alwaysOnTopButton
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 38)

                    Divider()

                    switch displayMode {
                    case .edit:
                        TextEditor(text: $bodyDraft, selection: $bodySelection)
                            .font(.system(size: 14 * zoomScale))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Color.white.opacity(0.46))
                            .focused($focusedField, equals: .body)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onAppear {
                                focusedField = .body
                            }
                            .onChange(of: bodyDraft) { _, newBody in
                                guard store.note(withID: noteID)?.body != newBody else { return }
                                store.updateBody(newBody, for: noteID)
                            }
                    case .preview:
                        FloatingMarkdownPreview(
                            markdown: note.body,
                            zoomScale: zoomScale
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Divider()

                    floatingNoteFooter(note)
                }
            } else {
                ContentUnavailableView("노트를 찾을 수 없음", systemImage: "exclamationmark.note")
            }
        }
        .frame(minWidth: 260, minHeight: 220)
        .background(noteColor.backgroundColor)
        .onChange(of: store.note(withID: noteID)?.body) { _, storedBody in
            guard let storedBody, storedBody != bodyDraft else { return }
            bodyDraft = storedBody
        }
        .alert("이 노트를 삭제하시겠습니까?", isPresented: $isDeleteConfirmationPresented) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive, action: onDelete)
        } message: {
            Text("삭제한 노트는 복구할 수 없습니다.")
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { store.note(withID: noteID)?.title ?? "" },
            set: { store.updateTitle($0, for: noteID) }
        )
    }

    private var colorBinding: Binding<NoteColor> {
        Binding(
            get: { store.note(withID: noteID)?.effectiveColor ?? .yellow },
            set: { store.updateColor($0, for: noteID) }
        )
    }

    private var zoomScale: Double {
        store.note(withID: noteID)?.effectiveZoomScale ?? 1
    }

    private var displayMode: NoteDisplayMode {
        store.note(withID: noteID)?.effectiveDisplayMode ?? .edit
    }

    private var noteColor: NoteColor {
        store.note(withID: noteID)?.effectiveColor ?? .yellow
    }

    private var isAlwaysOnTop: Bool {
        store.note(withID: noteID)?.effectiveIsAlwaysOnTop ?? true
    }

    private var alwaysOnTopButton: some View {
        let isOn = isAlwaysOnTop

        return Button {
            store.updateAlwaysOnTop(!isOn, for: noteID)
        } label: {
            Image(systemName: isOn
                ? "square.2.layers.3d.top.filled"
                : "square.2.layers.3d.bottom.filled")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 27, height: 27)
                .background(
                    isOn ? Color.white.opacity(0.72) : Color.clear,
                    in: Circle()
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("항상 맨 앞에 표시")
        .accessibilityValue(isOn ? "켜짐" : "꺼짐")
        .help(isOn
            ? "항상 맨 앞에 표시 중 · 클릭하면 다른 창 아래로 갈 수 있습니다"
            : "다른 창에 가려질 수 있음 · 클릭하면 항상 맨 앞에 고정됩니다")
    }

    private func floatingNoteFooter(_ note: Note) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                colorPicker
                zoomControls
                Spacer(minLength: 0)
                timestampLabel(for: note)
                deleteButton
            }
            .frame(minWidth: 300)

            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    colorPicker
                    Spacer(minLength: 0)
                    timestampLabel(for: note)
                    deleteButton
                }

                HStack {
                    Spacer(minLength: 0)
                    zoomControls
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }

    private var colorPicker: some View {
        Picker("노트 색상", selection: colorBinding) {
            ForEach(NoteColor.allCases) { color in
                Label {
                    Text(panelState.colorName(for: color))
                        .lineLimit(1)
                } icon: {
                    Image(nsImage: color.menuSwatchImage)
                }
                .tag(color)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 86, alignment: .leading)
        .help("노트 색상")
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button(action: zoomOut) {
                zoomStepLabel(systemImage: "minus")
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(zoomScale <= 0.5)
            .help("축소 (⌘-)")

            Button(action: resetZoom) {
                Text(zoomScale, format: .percent.precision(.fractionLength(0)))
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(width: 40, height: 24)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut("0", modifiers: .command)
            .help("100%로 복원 (⌘0)")

            Button(action: zoomIn) {
                zoomStepLabel(systemImage: "plus")
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(zoomScale >= 2)
            .help("확대 (⌘+)")
        }
        .padding(2)
        .background(
            Color.black.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .fixedSize()
    }

    private func timestampLabel(for note: Note) -> some View {
        Text(Self.compactTimestampFormatter.string(from: note.updatedAt))
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize()
            .help(note.updatedAt.formatted(date: .long, time: .standard))
    }

    private var deleteButton: some View {
        Button {
            isDeleteConfirmationPresented = true
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(.red)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("노트 삭제")
        .help("노트 삭제")
    }

    private func focusBodyAtBeginning() {
        bodySelection = TextSelection(insertionPoint: bodyDraft.startIndex)

        if displayMode != .edit {
            store.updateDisplayMode(.edit, for: noteID)
        }

        DispatchQueue.main.async {
            focusedField = .body
        }
    }

    private func displayModeButton(
        _ mode: NoteDisplayMode,
        systemImage: String,
        label: String
    ) -> some View {
        let isSelected = displayMode == mode

        return Button {
            guard !isSelected else { return }
            store.updateDisplayMode(mode, for: noteID)
        } label: {
            Image(systemName: isSelected ? "\(systemImage).fill" : systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 27, height: 27)
                .background(
                    isSelected ? Color.white.opacity(0.72) : Color.clear,
                    in: Circle()
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
        .help(isSelected ? "현재 \(label)" : "\(label)로 전환")
    }

    private enum FocusedField: Hashable {
        case title
        case body
    }

    private func zoomIn() {
        setZoom(zoomScale + 0.1)
    }

    private func zoomStepLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 26, height: 22)
            .background(
                Color.white.opacity(0.52),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .contentShape(Rectangle())
    }

    private func zoomOut() {
        setZoom(zoomScale - 0.1)
    }

    private func resetZoom() {
        setZoom(1)
    }

    private func setZoom(_ scale: Double) {
        let roundedScale = (scale * 10).rounded() / 10
        store.updateZoomScale(roundedScale, for: noteID)
    }
}
