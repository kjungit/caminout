import CamZoomCore
import CamZoomShared
import SwiftUI
import UniformTypeIdentifiers

/// 설정 창 (종합 문서 4장).
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var confirmRemoval = false
    @AppStorage("showDebugOverlay") private var showDebugOverlay = false
    @State private var exportStatus: String?
    @State private var exporting = false

    var body: some View {
        @Bindable var app = app
        Form {
            Section("카메라") {
                Picker("입력", selection: $app.settings.output.input) {
                    Text("기본 카메라").tag(InputSource.camera(id: nil))
                    ForEach(app.availableCameras) { camera in
                        Text(camera.name).tag(InputSource.camera(id: camera.id))
                    }
                    Divider()
                    Text("색 막대 (검증용)").tag(InputSource.colorBars)
                    if case .image(let path) = app.settings.output.input {
                        Text(URL(fileURLWithPath: path).lastPathComponent).tag(app.settings.output.input)
                    }
                }
                Button("이미지·영상 파일을 입력으로…", action: chooseFile)
                LabeledContent("출력 해상도") {
                    Text("\(app.outputFormat.description) · 화상 앱이 고름")
                        .foregroundStyle(.secondary)
                }
                Picker("비율이 다를 때", selection: $app.settings.output.fitMode) {
                    ForEach(OutputFitMode.allCases) { Text($0.label).tag($0) }
                }
                Text("macOS 비디오 효과(인물 모드, 센터 스테이지 등)를 켜면 그 효과가 들어간 영상에 이 앱의 설정이 더해져요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("일반") {
                Picker("화면 모드", selection: $app.settings.preferences.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("메뉴바 아이콘만 표시 (Dock에 안 보이기)", isOn: $app.settings.preferences.menuBarOnly)
                Toggle("맥이 뜨겁거나 저전력 모드일 때 자동으로 품질 낮추기", isOn: $app.settings.preferences.autoQualityReduction)
            }

            Section("가상 카메라") {
                LabeledContent("상태", value: app.extensionManager.state.label)
                LabeledContent("화상 앱 사용", value: app.cameraStatus.inUse ? "사용 중" : "사용 안 함")
                LabeledContent("버전") {
                    Text("앱 \(app.extensionManager.appBuild) · 익스텐션 \(app.cameraStatus.extensionBuild ?? app.extensionManager.installedBuild ?? "-") · 프로토콜 \(app.cameraStatus.protocolVersion.map(String.init) ?? "-")")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("설치 안내 열기") { openWindow(id: "install") }
                    Button("다시 설치") { app.extensionManager.activate() }
                    Spacer()
                    Button("가상 카메라 제거…", role: .destructive) { confirmRemoval = true }
                }
                Text("제거가 안 되면 시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램 > 카메라 확장 프로그램에서 \(CameraIdentity.productName)를 끄거나 삭제해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("문제 신고") {
                Button(exporting ? "만드는 중…" : "진단 정보 내보내기…", action: exportDiagnostics)
                    .disabled(exporting)
                Text("앱 정보, 설정, 이번 실행의 로그, macOS가 모은 충돌·성능 진단을 zip 하나로 저장해요. 영상과 사진은 들어가지 않고, 어디로도 자동으로 보내지 않아요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let exportStatus {
                    Text(exportStatus).font(.caption)
                }
            }

            Section("검증·개발") {
                Toggle("출력에 프레임 번호 표시", isOn: $app.settings.output.showFrameNumber)
                Toggle("미리보기에 측정값 표시", isOn: $showDebugOverlay)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 560)
        .tint(Theme.accent)
        .onAppear {
            app.refreshCameras()
            launchAtLogin = LoginItem.isEnabled
        }
        .confirmationDialog("가상 카메라를 제거할까요?", isPresented: $confirmRemoval) {
            Button("제거", role: .destructive) { app.extensionManager.deactivate() }
        } message: {
            Text("화상 앱 카메라 목록에서 \(CameraIdentity.deviceName)가 사라져요. 앱을 지우기 전에 먼저 제거해 주세요.")
        }
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "\(CameraIdentity.productName)-진단.zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exporting = true
        exportStatus = nil
        Task {
            do {
                try await app.exportDiagnostics(to: url)
                exportStatus = "저장했어요: \(url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                exportStatus = "저장하지 못했어요: \(error.localizedDescription)"
            }
            exporting = false
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            app.settings.output.input = .image(path: url.path)
        }
    }
}
