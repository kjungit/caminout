import CamZoomCore
import SwiftUI

/// 메인 창 오른쪽 "조절" 패널: 원본 썸네일과 확대 영역, 확대, 비율, 반전·회전, 초기화, 프리셋.
struct AdjustPanel: View {
    @Environment(AppState.self) private var app
    @State private var presetName = ""

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("원본 화면") {
                    CropSelector()
                    Text("클릭하거나 드래그해서 확대할 위치를 정하세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                section("확대") {
                    HStack {
                        Slider(value: $app.settings.crop.zoom, in: CropState.zoomRange)
                        Text(String(format: "%.1f배", app.settings.crop.zoom))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                section("비율") {
                    Picker("비율", selection: $app.settings.crop.aspect) {
                        ForEach(AspectOption.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if app.settings.crop.aspect != .original, app.outputAspect > 1.01 {
                        Picker("출력에 맞추기", selection: $app.settings.output.fitMode) {
                            ForEach(OutputFitMode.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .font(.caption)
                    }
                }

                section("방향") {
                    HStack {
                        Toggle("좌우 반전", isOn: $app.settings.crop.mirrored)
                        Spacer()
                        Button {
                            app.rotateClockwise()
                        } label: {
                            Label("회전 \(app.settings.crop.rotation.label)", systemImage: "rotate.right")
                        }
                    }
                }

                HStack {
                    Button("가운데로") {
                        app.settings.crop.centerX = 0.5
                        app.settings.crop.centerY = 0.5
                    }
                    Button("초기화") { app.resetCrop() }
                }

                section("프리셋") {
                    ForEach(app.presets) { preset in
                        HStack {
                            Button(preset.name) { app.apply(preset) }
                                .buttonStyle(.link)
                            Spacer()
                            Button {
                                app.delete(preset)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("프리셋 삭제")
                        }
                    }
                    HStack {
                        TextField("이름", text: $presetName)
                            .onSubmit(save)
                        Button("현재 설정 저장", action: save)
                            .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .padding(16)
        }
    }

    private func save() {
        app.savePreset(named: presetName)
        presetName = ""
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}
