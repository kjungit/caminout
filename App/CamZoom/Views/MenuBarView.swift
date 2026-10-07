import CamZoomCore
import CamZoomShared
import SwiftUI

/// 메뉴바 팝오버: 통화 중 빠른 조작 (종합 문서 4장).
struct MenuBarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(CameraIdentity.productName).font(.headline)
                Spacer()
                Toggle("효과", isOn: $app.settings.output.effectsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help("효과 전체 켜기·끄기")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("현재 출력").font(.caption).foregroundStyle(.secondary)
                OutputPreviewPanel(cornerRadius: 8)
                HStack(spacing: 6) {
                    Circle()
                        .fill(app.cameraStatus.inUse ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(app.virtualCameraSummary).font(.caption).lineLimit(1)
                }
            }

            HStack {
                Text("확대").font(.callout)
                Slider(value: $app.settings.crop.zoom, in: CropState.zoomRange)
                Text(String(format: "%.1f배", app.settings.crop.zoom))
                    .font(.callout)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }

            if !app.presets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("프리셋").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(app.presets) { preset in
                                Button(preset.name) { app.apply(preset) }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }

            if let message = app.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }

            Divider()

            HStack {
                Button("메인 창 열기") {
                    open("main")
                }
                .keyboardShortcut("o")
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .help("설정")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("종료")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 320)
        .tint(Theme.accent)
    }

    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }
}
