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
    /// 자동 품질 낮춤 단계와 그 이유 (설계서 9.3).
    private(set) var qualityLevel: QualityLevel = .normal
    private(set) var qualityConditions = QualityConditions()

    let extensionManager = ExtensionManager()
    let previewHub = PreviewHub()

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let pipeline = FramePipeline()
    @ObservationIgnored private let monitor = VirtualCameraMonitor()
    @ObservationIgnored private let activity = StreamingActivity()
    @ObservationIgnored private let quality = QualityMonitor()
    @ObservationIgnored private let diagnostics = DiagnosticsCollector()
    @ObservationIgnored private var previewDemand = 0
    @ObservationIgnored private var checkedVersion = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.kjungit.caminout", category: "app")

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.settings = store.load()
        self.presets = store.loadPresets()
        wirePipeline()
        wireQuality()
        diagnostics.start()
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

    /// 품질을 낮췄을 때 메뉴바 팝오버에 보이는 한 줄. 정상이면 nil.
    var qualityNotice: String? {
        guard qualityLevel > .normal else { return nil }
        guard let reason = qualityConditions.reason else {
            return "품질을 낮춘 상태예요. 30초마다 한 단계씩 돌아가요 (\(qualityLevel.rawValue)단계)"
        }
        let effect = qualityLevel.outputFPSLimit.map { "출력을 \($0)fps로" } ?? "효과 품질을"
        return "\(reason) \(effect) 낮췄어요 (\(qualityLevel.rawValue)단계)"
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

    /// 진단 묶음(zip)을 만든다 (G13). 로그 읽기와 압축은 주 스레드 밖에서 한다.
    func exportDiagnostics(to destination: URL) async throws {
        let summary = diagnosticsSummary()
        try await Task.detached(priority: .userInitiated) {
            try DiagnosticsExporter.export(summary: summary, to: destination)
        }.value
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
            Task { @MainActor in
                self?.stats = stats
                self?.quality.record(stats)
            }
        }
        pipeline.onError = { [weak self] error in
            Task { @MainActor in self?.errorMessage = error.message }
        }
    }

    private func wireQuality() {
        quality.onChange = { [weak self] level, conditions in
            guard let self else { return }
            qualityLevel = level
            qualityConditions = conditions
            pushConfig()
        }
        quality.setEnabled(settings.preferences.autoQualityReduction)
    }

    private func pushConfig() {
        pipeline.update(PipelineConfig(settings: settings, outputSize: outputFormat.size, quality: qualityLevel))
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
            quality.captureStopped()
            sourceThumbnail = nil
            previewHub.clear()
        }
    }

    private func diagnosticsSummary() -> String {
        let info = ProcessInfo.processInfo
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        return """
        \(CameraIdentity.productName) 진단 정보
        만든 시각: \(Date().formatted(.iso8601))

        앱: \(version) (\(extensionManager.appBuild))
        익스텐션: \(cameraStatus.extensionBuild ?? extensionManager.installedBuild ?? "-"), 상태 \(extensionManager.state.label)
        프로토콜: 앱 \(CameraIdentity.protocolVersion), 익스텐션 \(cameraStatus.protocolVersion.map(String.init) ?? "-")
        macOS: \(info.operatingSystemVersionString)
        기기: \(Self.hardwareModel()), 메모리 \(info.physicalMemory / 1_073_741_824)GB
        발열: \(info.thermalState.rawValue), 저전력 모드: \(info.isLowPowerModeEnabled)
        품질 단계: \(qualityLevel.rawValue) (자동 낮춤 \(settings.preferences.autoQualityReduction ? "켬" : "끔"))

        화상 앱 사용 중: \(cameraStatus.inUse), 출력 형식: \(outputFormat.description)
        캡처 중: \(isCapturing), 입력: \(settings.output.input)
        출력 \(String(format: "%.1f", stats.outputFPS))fps, 합성 p95 \(String(format: "%.1f", stats.renderP95))ms, 버림 합성 \(stats.droppedBusy)·sink \(stats.droppedSink), 풀 고갈 \(stats.poolExhausted)

        익스텐션 로그는 들어 있지 않아요. 필요하면 터미널에서:
        log show --last 1h --predicate 'subsystem BEGINSWITH "com.kjungit.caminout"' --info
        """
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    private func applyPreferences() {
        quality.setEnabled(settings.preferences.autoQualityReduction)
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
