import AppKit
import CamZoomShared
import os
import SystemExtensions

/// 카메라 익스텐션 설치·교체·제거 (설계서 3장 SystemExtensions, G1·G2·G5).
@MainActor
@Observable
final class ExtensionManager: NSObject {

    enum State: Equatable {
        case unknown
        case notInstalled
        case activating
        /// 시스템 설정에서 사용자가 허용해야 한다.
        case awaitingApproval
        case installed
        case willCompleteAfterReboot
        case removing
        case failed(String)

        var label: String {
            switch self {
            case .unknown: return "확인 중"
            case .notInstalled: return "설치 안 됨"
            case .activating: return "설치 중"
            case .awaitingApproval: return "시스템 설정에서 허용 필요"
            case .installed: return "설치됨"
            case .willCompleteAfterReboot: return "재시동 후 완료"
            case .removing: return "제거 중"
            case .failed(let message): return "오류: \(message)"
            }
        }
    }

    private(set) var state: State = .unknown
    /// 시스템에 설치된 익스텐션의 빌드 번호.
    private(set) var installedBuild: String?
    /// 설치 직후 앱을 다시 열어야 가상 카메라가 보이는 사례가 있다 (G1).
    private(set) var needsAppRelaunch = false

    fileprivate enum RequestKind { case properties, activation, deactivation }
    /// 진행 중인 요청의 종류. 결과 콜백에서 어떤 요청이었는지 구분한다.
    @ObservationIgnored private var pending: [ObjectIdentifier: RequestKind] = [:]

    private let identifier = CameraIdentity.extensionBundleID
    private let logger = Logger(subsystem: "com.kjungit.caminout", category: "extension")

    /// 앱이 응용 프로그램 폴더에 있어야 확장을 설치할 수 있다 (설계서 10.3).
    var isInApplicationsFolder: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// 설치 상태를 다시 확인한다.
    func refresh() {
        submit(.propertiesRequest(forExtensionWithIdentifier: identifier, queue: .main), kind: .properties)
    }

    /// 설치하거나, 이미 설치돼 있으면 이 앱에 든 버전으로 교체한다.
    func activate() {
        guard isInApplicationsFolder else {
            state = .failed("앱을 응용 프로그램 폴더로 옮긴 뒤 다시 실행해 주세요.")
            return
        }
        state = .activating
        submit(.activationRequest(forExtensionWithIdentifier: identifier, queue: .main), kind: .activation)
        logger.info("익스텐션 설치 요청")
    }

    /// 가상 카메라 제거 (G2). 앱을 휴지통에 넣어도 확장이 남는 버그가 있어, 설치한 앱이 직접 제거를 요청한다.
    func deactivate() {
        state = .removing
        submit(.deactivationRequest(forExtensionWithIdentifier: identifier, queue: .main), kind: .deactivation)
        logger.info("익스텐션 제거 요청")
    }

    private func submit(_ request: OSSystemExtensionRequest, kind: RequestKind) {
        pending[ObjectIdentifier(request)] = kind
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    fileprivate func finish(_ request: ObjectIdentifier) -> RequestKind? {
        pending.removeValue(forKey: request)
    }

    /// 시스템 설정의 확장 화면을 연다.
    func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    /// 앱을 다시 연다 (G1).
    func relaunchApp() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - 결과 처리 (주 스레드)

    fileprivate func handle(result: OSSystemExtensionRequest.Result, isDeactivation: Bool) {
        switch result {
        case .completed:
            if isDeactivation {
                state = .notInstalled
                installedBuild = nil
            } else {
                state = .installed
                installedBuild = appBuild
                needsAppRelaunch = true
            }
        case .willCompleteAfterReboot:
            state = .willCompleteAfterReboot
        @unknown default:
            state = .failed("알 수 없는 결과")
        }
        logger.info("익스텐션 요청 완료: \(String(describing: self.state), privacy: .public)")
    }

    fileprivate func handle(error: Error) {
        let nsError = error as NSError
        logger.error("익스텐션 요청 실패: \(nsError.domain, privacy: .public) \(nsError.code) \(nsError.localizedDescription, privacy: .public)")
        if nsError.domain == OSSystemExtensionErrorDomain {
            switch OSSystemExtensionError.Code(rawValue: nsError.code) {
            case .unsupportedParentBundleLocation:
                state = .failed("앱을 응용 프로그램 폴더로 옮긴 뒤 다시 실행해 주세요.")
                return
            case .extensionNotFound:
                state = .notInstalled
                return
            case .requestCanceled, .requestSuperseded:
                return
            case .authorizationRequired:
                state = .awaitingApproval
                return
            default:
                break
            }
        }
        state = .failed(nsError.localizedDescription)
    }

    /// 시스템이 알려 준 설치 정보 중 필요한 값만 옮긴 것.
    fileprivate struct InstalledInfo: Sendable {
        let isEnabled: Bool
        let isUninstalling: Bool
        let isAwaitingUserApproval: Bool
        let bundleVersion: String
    }

    fileprivate func handle(properties: [InstalledInfo]) {
        let enabled = properties.first(where: { $0.isEnabled && !$0.isUninstalling })
        if let enabled {
            state = .installed
            installedBuild = enabled.bundleVersion
        } else if properties.contains(where: { $0.isAwaitingUserApproval }) {
            state = .awaitingApproval
        } else {
            state = .notInstalled
            installedBuild = nil
        }
        logger.info("익스텐션 상태: \(String(describing: self.state), privacy: .public) build=\(self.installedBuild ?? "-", privacy: .public) app=\(self.appBuild, privacy: .public)")
    }
}

extension ExtensionManager: OSSystemExtensionRequestDelegate {

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        // 앱과 익스텐션 버전을 맞추기 위해 항상 앱에 든 버전으로 교체한다 (G5).
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        MainActor.assumeIsolated { state = .awaitingApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let id = ObjectIdentifier(request)
        MainActor.assumeIsolated { handle(result: result, isDeactivation: finish(id) == .deactivation) }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let id = ObjectIdentifier(request)
        MainActor.assumeIsolated {
            _ = finish(id)
            handle(error: error)
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let id = ObjectIdentifier(request)
        let infos = properties.map {
            InstalledInfo(
                isEnabled: $0.isEnabled,
                isUninstalling: $0.isUninstalling,
                isAwaitingUserApproval: $0.isAwaitingUserApproval,
                bundleVersion: $0.bundleVersion
            )
        }
        MainActor.assumeIsolated {
            _ = finish(id)
            handle(properties: infos)
        }
    }
}
