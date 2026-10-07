import CamZoomShared
import SwiftUI

@main
struct CamZoomApp: App {
    @State private var app = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(app)
        } label: {
            Image(systemName: app.cameraStatus.inUse ? "video.fill" : "video")
                .accessibilityLabel(CameraIdentity.productName)
        }
        .menuBarExtraStyle(.window)

        Window(CameraIdentity.productName, id: "main") {
            MainWindowView()
                .environment(app)
                .task { showInstallGuideIfNeeded() }
        }
        .defaultSize(width: 1100, height: 680)

        Window("설치 안내", id: "install") {
            InstallGuideView()
                .environment(app)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(app)
        }
    }

    @Environment(\.openWindow) private var openWindow

    /// 첫 실행이거나 가상 카메라가 없으면 설치 안내를 띄운다.
    @MainActor
    private func showInstallGuideIfNeeded() {
        if !app.settings.preferences.onboardingCompleted {
            openWindow(id: "install")
        }
    }
}
