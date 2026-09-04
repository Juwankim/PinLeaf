//
//  PanelSettingsView.swift
//  PinLeaf
//

import SwiftUI

struct PanelSettingsView: View {
    @ObservedObject var panelState: PanelPresentationState

    var body: some View {
        ScrollView {
            settingsContent
        }
        .frame(width: 320)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("노트 목록 패널")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("목록 위치")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("목록 위치", selection: edgeBinding) {
                    Text("왼쪽").tag(ScreenEdge.left)
                    Text("오른쪽").tag(ScreenEdge.right)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("노트 목록 패널 너비")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(panelState.panelWidth.rounded())) pt")
                        .font(.caption.monospacedDigit())
                }

                Slider(value: panelWidthBinding, in: 180...350, step: 10)
                    .controlSize(.regular)

                Text("패널이 펼쳐졌을 때만 적용됩니다. 접혔을 때는 아래 ‘접힌 상태 노출 너비’만 적용됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: showsDockIconBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("앱 실행 시 Dock 아이콘 표시")

                    Text("즉시 적용되며 다음 실행에도 유지됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            Text("노트 목록")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Picker("목록 표시량", selection: noteListDisplayLimitBinding) {
                    ForEach(NoteListDisplayLimit.allCases) { limit in
                        Text(limit.settingsTitle).tag(limit)
                    }
                }
                .pickerStyle(.menu)

                Text("최대 \(panelState.noteListDisplayLimit.maximumCount)개의 노트를 표시합니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("구분")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("기본")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(NoteColor.allCases) { color in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(color.backgroundColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.black.opacity(0.18), lineWidth: 1)
                            )
                            .frame(width: 32, height: 16)

                        TextField(
                            color.displayName,
                            text: colorNameBinding(for: color)
                        )
                        .textFieldStyle(.roundedBorder)

                        Button {
                            panelState.setDefaultNoteColor(color)
                        } label: {
                            Image(
                                systemName: panelState.defaultNoteColor == color
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .font(.system(size: 16))
                            .foregroundStyle(
                                panelState.defaultNoteColor == color
                                    ? Color.accentColor
                                    : Color.secondary
                            )
                        }
                        .buttonStyle(.plain)
                        .help("새 노트 기본 색상으로 설정")
                    }
                }

                Text("‘구분’ 이름은 왼쪽 패널 색상 메뉴와 목록에 표시됩니다. ‘기본’으로 표시한 색상은 목록에서 ‘전체 색상’일 때 새 노트에 사용됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            settingSlider(
                title: "접힌 상태 노출 너비",
                value: collapsedPeekWidthBinding,
                range: 2...20,
                step: 1,
                valueLabel: { "\(Int($0.rounded())) pt" }
            )

            Divider()

            Button("기본값으로 복원", action: panelState.resetPanelSettings)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(width: 320)
    }

    private var edgeBinding: Binding<ScreenEdge> {
        Binding(
            get: { panelState.edge },
            set: { panelState.setEdge($0) }
        )
    }

    private var showsDockIconBinding: Binding<Bool> {
        Binding(
            get: { panelState.showsDockIcon },
            set: { panelState.setShowsDockIcon($0) }
        )
    }

    private var collapsedPeekWidthBinding: Binding<Double> {
        Binding(
            get: { panelState.collapsedPeekWidth },
            set: { panelState.setCollapsedPeekWidth($0) }
        )
    }

    private var panelWidthBinding: Binding<Double> {
        Binding(
            get: { panelState.panelWidth },
            set: { panelState.setPanelWidth($0) }
        )
    }

    private var noteListDisplayLimitBinding: Binding<NoteListDisplayLimit> {
        Binding(
            get: { panelState.noteListDisplayLimit },
            set: { panelState.setNoteListDisplayLimit($0) }
        )
    }

    private func colorNameBinding(for color: NoteColor) -> Binding<String> {
        Binding(
            get: { panelState.colorName(for: color) },
            set: { panelState.setColorName($0, for: color) }
        )
    }

    private func settingSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 0.01,
        valueLabel: @escaping (Double) -> String = { value in
            value.formatted(.percent.precision(.fractionLength(0)))
        }
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(valueLabel(value.wrappedValue))
                    .font(.caption.monospacedDigit())
            }

            Slider(value: value, in: range, step: step)
                .controlSize(.regular)
        }
    }
}
