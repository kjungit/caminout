import AppKit
import os
import ServiceManagement

/// 로그인 시 자동 실행 (G12). 상태는 시스템이 가지므로 따로 저장하지 않는다.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// 스트리밍 중 App Nap을 막는다 (G4). 메뉴바 앱은 창이 안 보이면 처리가 느려질 수 있다.
@MainActor
final class StreamingActivity {
    private var token: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.kjungit.caminout", category: "activity")

    var isActive: Bool { token != nil }

    func setActive(_ active: Bool) {
        if active, token == nil {
            token = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "가상 카메라로 영상을 보내는 중"
            )
            logger.info("App Nap 방지 시작")
        } else if !active, let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
            logger.info("App Nap 방지 해제")
        }
    }
}
