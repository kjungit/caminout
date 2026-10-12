import CamZoomShared
import SwiftUI

/// 첫 실행 설치 안내 5단계 (종합 문서 4장, 기획서 6.1). 목표는 설치 완료까지 3분 이내.
struct InstallGuideView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var step = 1

    private let total = 5

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 6) {
                ForEach(1...total, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.accent : Color.secondary.opacity(0.3))
                        .frame(width: index == step ? 22 : 8, height: 8)
                }
            }

            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)
                .frame(width: 88, height: 88)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))

            VStack(spacing: 8) {
                Text("\(step) / \(total)").font(.caption).foregroundStyle(.secondary)
                Text(title).font(.title2.weight(.semibold))
                Text(description)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 420)

            stepContent
                .frame(maxWidth: 420)

            Spacer(minLength: 0)

            HStack {
                Button("이전") { step -= 1 }
                    .disabled(step == 1)
                Spacer()
                Button(step == total ? "완료" : "다음") {
                    if step == total {
                        app.settings.preferences.onboardingCompleted = true
                        dismiss()
                    } else {
                        step += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 560)
        .tint(Theme.accent)
        .onAppear { app.extensionManager.refresh() }
    }

    private var icon: String {
        switch step {
        case 1: return "camera"
        case 2, 3: return "puzzlepiece.extension"
        case 4: return "crop"
        default: return "checkmark"
        }
    }

    private var title: String {
        switch step {
        case 1: return "카메라 권한 허용"
        case 2: return "가상 카메라 설치 요청"
        case 3: return "시스템 설정에서 확장 허용"
        case 4: return "미리보기에서 확대·비율 설정"
        default: return "설치 완료"
        }
    }

    private var description: String {
        switch step {
        case 1: return "맥의 카메라에 접근할 수 있도록 권한을 허용해 주세요. 영상은 기기 밖으로 나가지 않아요."
        case 2: return "Zoom·Discord에서 선택할 수 있는 가상 카메라를 설치할게요. 한 번만 하면 돼요."
        case 3: return "시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램에서 \(CameraIdentity.productName) 카메라 확장을 허용해 주세요."
        case 4: return "원하는 위치로 확대하고 비율을 골라 보세요. 설정은 자동으로 저장돼요."
        default: return "이제 Zoom이나 Discord의 카메라 목록에서 \(CameraIdentity.deviceName)을 한 번만 선택하면 돼요."
        }
    }

    @ViewBuilder private var stepContent: some View {
        let manager = app.extensionManager
        switch step {
        case 1:
            if app.cameraAuthorized {
                Label("허용됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("카메라 권한 허용") { Task { await app.requestCameraAccess() } }
                    .buttonStyle(.borderedProminent)
            }
        case 2:
            VStack(spacing: 8) {
                if !manager.isInApplicationsFolder {
                    Label("앱을 응용 프로그램 폴더로 옮긴 뒤 다시 실행해야 설치할 수 있어요.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if manager.state == .installed {
                    Label("설치됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("가상 카메라 설치") { manager.activate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(manager.state == .activating)
                    Text(manager.state.label).font(.caption).foregroundStyle(.secondary)
                }
            }
        case 3:
            VStack(spacing: 8) {
                Button("시스템 설정 열기") { manager.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                Text("상태: \(manager.state.label)").font(.caption).foregroundStyle(.secondary)
                if manager.needsAppRelaunch || (manager.state == .installed && !app.cameraStatus.installed) {
                    Text("허용한 뒤에도 가상 카메라가 보이지 않으면 앱을 다시 열어 주세요. 화상 앱도 다시 열어야 할 수 있어요.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("앱 다시 열기") { manager.relaunchApp() }
                }
            }
        case 4:
            HStack(alignment: .top, spacing: 12) {
                CropSelector().frame(width: 200)
                OutputPreviewPanel(cornerRadius: 8).frame(width: 200)
            }
        default:
            Text("내 화상 앱 화면은 좌우가 반전돼 보일 수 있지만 상대방에게는 정상으로 보여요. 카메라가 목록에 없으면 화상 앱을 다시 열어 주세요.")
                .font(.callout)
                .multilineTextAlignment(.center)
        }
    }
}
