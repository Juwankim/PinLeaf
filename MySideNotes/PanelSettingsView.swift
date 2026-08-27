//
//  PanelSettingsView.swift
//  PinLeaf
//

import SwiftUI

struct PanelSettingsView: View {
    @ObservedObject var panelState: PanelPresentationState

    var body: some View {
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

            Divider()

            settingSlider(
                title: "비활성 투명도",
                value: inactiveOpacityBinding,
                range: 0.10...0.90
            )

            settingSlider(
                title: "접힌 상태 노출 비율",
                value: collapsedVisibleFractionBinding,
                range: 0.05...0.30
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

    private var inactiveOpacityBinding: Binding<Double> {
        Binding(
            get: { panelState.inactiveOpacity },
            set: { panelState.setInactiveOpacity($0) }
        )
    }

    private var showsDockIconBinding: Binding<Bool> {
        Binding(
            get: { panelState.showsDockIcon },
            set: { panelState.setShowsDockIcon($0) }
        )
    }

    private var collapsedVisibleFractionBinding: Binding<Double> {
        Binding(
            get: { panelState.collapsedVisibleFraction },
            set: { panelState.setCollapsedVisibleFraction($0) }
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

    private func settingSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
            }

            Slider(value: value, in: range, step: 0.01)
                .controlSize(.regular)
        }
    }
}
