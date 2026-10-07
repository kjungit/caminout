import AppKit
import CameraBridge
import CamZoomCore
import CamZoomShared
import CaptureKit
import Foundation
import os

/// 앱 상태 하나 (설계서 8장). 주 스레드에서만 바꾸고, 파이프라인에는 불변 스냅샷만 넘긴다.
@MainActor
@Observable
final class AppState {

    // MARK: 저장되는 상태

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            store.scheduleSave(settings)
            pushConfig()
            if settings.output.input != oldValue.output.input { updateCapture(forceRestart: true) }
            if settings.preferences != oldValue.preferences { applyPreferences() }
        }
    }
    private(set) var presets: [Preset] = []

    // MARK: 실행 중 상태 (저장 안 함)

    private(set) var cameraStatus = VirtualCameraStatus()
    private(set) var stats = PipelineStats()
    private(set) var sourceThumbnail: CGImage?
    /// 반전·회전 전 원본 크기.
    private(set) var sourceSize = CGSize(width: 1920, height: 1080)
    private(set) var errorMessage: String?
    private(set) var isCapturing = false
    private(set) var availableCameras: [CameraDeviceInfo] = []
    private(set) var cameraAuthorized = CameraAuthorization.isAuthorized

    let extensionManager = ExtensionManager()
    let previewHub = PreviewHub()

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let pipeline = FramePipeline()
    @ObservationIgnored private let monitor = VirtualCameraMonitor()
    @ObservationIgnored private let activity = StreamingActivity()
    @ObservationIgnored private var previewDemand = 0
    @ObservationIgnored private var checkedVersion = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.kjungit.caminout", category: "app")

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.settings = store.load()
        self.presets = store.loadPresets()
        wirePipeline()
        pushConfig()
        applyPreferences()
        refreshCameras()

        monitor.start { [weak self] status in
            Task { @MainActor in self?.didChange(status) }
        }
        extensionManager.refresh()

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        }
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // 잠자기에서 깨면 카메라를 다시 연다.
            MainActor.assumeIsolated { self?.updateCapture(forceRestart: true) }
        }
    }

    // MARK: - 파생 값

    /// 화상 앱이 고른 출력 형식. 아무도 쓰지 않으면 기본 16:9.
    var outputFormat: OutputFormat {
        cameraStatus.activeFormat ?? .default
    }

    /// 미리보기 화면 비율.
    var outputAspect: CGFloat {
        CGFloat(outputFormat.width) / CGFloat(outputFormat.height)
    }

    /// 반전·회전 뒤 원본 크기. 확대 영역 상자는 이 크기 기준이다.
    var orientedSourceSize: CGSize {
        CropMath.orientedSize(source: sourceSize, rotation: settings.crop.rotation)
    }

    var virtualCameraSummary: String {
        if !cameraStatus.installed {
            return extensionManager.state == .installed ? "가상 카메라 준비 중" : "가상 카메라 \(extensionManager.state.label)"
        }
        return cameraStatus.inUse ? "화상 앱에서 사용 중" : "대기 중 (화상 앱에서 \(CameraIdentity.deviceName) 선택)"
    }

    // MARK: - 미리보기 창이 열리고 닫힐 때

    /// 미리보기가 보이는 동안에는 화상 앱이 쓰지 않아도 카메라를 켠다.
    func previewAppeared() {
        previewDemand += 1
        updateCapture()
    }

    func previewDisappeared() {
        previewDemand = max(0, previewDemand - 1)
        updateCapture()
    }

    // MARK: - 사용자 동작

    func resetCrop() {
        let keep = settings.crop
        settings.crop = CropState(mirrored: keep.mirrored, rotation: keep.rotation)
    }

    func rotateClockwise() {
        settings.crop.rotation = settings.crop.rotation.next
    }

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = Preset(name: trimmed, crop: settings.crop)
        store.save(preset)
        presets = store.loadPresets()
    }

    func apply(_ preset: Preset) {
        settings.crop = preset.crop.sanitized
    }

    func delete(_ preset: Preset) {
        store.deletePreset(id: preset.id)
        presets = store.loadPresets()
    }

    func requestCameraAccess() async {
        cameraAuthorized = await CameraAuthorization.request()
        refreshCameras()
        updateCapture(forceRestart: true)
    }

    func refreshCameras() {
        cameraAuthorized = CameraAuthorization.isAuthorized
        availableCameras = CameraDevices.available(
            excludingIDs: [CameraIdentity.deviceUID],
            excludingNames: [CameraIdentity.deviceName]
        )
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - 내부

    private func wirePipeline() {
        let hub = previewHub
        pipeline.onOutput = { frame in
            DispatchQueue.main.async { MainActor.assumeIsolated { hub.publish(frame) } }
        }
        pipeline.onThumbnail = { [weak self] thumbnail in
            Task { @MainActor in
                guard let self else { return }
                self.sourceThumbnail = thumbnail.image
                if self.sourceSize != thumbnail.sourceSize { self.sourceSize = thumbnail.sourceSize }
            }
        }
        pipeline.onStats = { [weak self] stats in
            Task { @MainActor in self?.stats = stats }
        }
        pipeline.onError = { [weak self] error in
            Task { @MainActor in self?.errorMessage = error.message }
        }
    }

    private func pushConfig() {
        pipeline.update(PipelineConfig(settings: settings, outputSize: outputFormat.size))
    }

    private func didChange(_ status: VirtualCameraStatus) {
        let formatChanged = status.activeFormat != cameraStatus.activeFormat
        cameraStatus = status
        if formatChanged { pushConfig() }
        activity.setActive(status.inUse)
        pipeline.setSinkEnabled(status.installed)
        updateCapture()

        // 앱과 익스텐션 버전이 다르면 교체를 요청한다 (G5).
        if status.installed, !checkedVersion {
            checkedVersion = true
            if status.versionMismatch {
                logger.warning("익스텐션 프로토콜 버전 불일치: \(String(describing: status.protocolVersion), privacy: .public)")
                extensionManager.activate()
            }
        }
    }

    /// 화상 앱이 가상 카메라를 쓰거나 미리보기가 열려 있을 때만 카메라를 켠다 (설계서 6장, 9.2).
    private func updateCapture(forceRestart: Bool = false) {
        let needed = cameraStatus.inUse || previewDemand > 0
        if forceRestart, isCapturing { pipeline.stop() }
        if needed {
            if case .camera = settings.output.input, !CameraAuthorization.isAuthorized {
                cameraAuthorized = false
                isCapturing = false
                return
            }
            errorMessage = nil
            pipeline.start(input: settings.output.input)
            isCapturing = true
        } else if isCapturing {
            pipeline.stop()
            isCapturing = false
            sourceThumbnail = nil
            previewHub.clear()
        }
    }

    private func applyPreferences() {
        switch settings.preferences.appearance {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
        NSApp?.setActivationPolicy(settings.preferences.menuBarOnly ? .accessory : .regular)
    }

    private func shutdown() {
        store.flush()
        monitor.stop()
        pipeline.setSinkEnabled(false)
        pipeline.stop()
    }
}
