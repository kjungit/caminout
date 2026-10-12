import CamZoomCore
import Foundation
import os

/// 발열·저전력 모드·프레임 누락을 보고 품질 단계를 정한다 (설계서 9.3).
///
/// 단계 계산은 CamZoomCore의 `QualityGovernor`가 하고, 여기서는 시스템 상태를 읽어 넣어 주기만 한다.
/// 파이프라인 측정값이 1초마다 들어오므로 그때마다 다시 계산하고, 발열·전원 알림이 오면 바로 계산한다.
@MainActor
final class QualityMonitor {
    private(set) var level: QualityLevel = .normal
    private(set) var conditions = QualityConditions()

    /// 단계나 조건이 바뀌면 불린다.
    var onChange: ((QualityLevel, QualityConditions) -> Void)?

    private var governor = QualityGovernor()
    private var drops = SustainedDropDetector()
    private var enabled = true
    /// AppState와 수명이 같아 따로 해제하지 않는다.
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: "com.kjungit.caminout", category: "quality")

    init() {
        let center = NotificationCenter.default
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            })
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        evaluate()
    }

    /// 파이프라인의 1초 측정값.
    func record(_ stats: PipelineStats) {
        drops.record(dropped: stats.droppedInWindow, delivered: stats.deliveredInWindow)
        evaluate()
    }

    /// 캡처를 멈추면 누락 기록을 지운다. 다시 켰을 때 예전 누락이 이어지지 않게 하기 위해서다.
    func captureStopped() {
        drops.reset()
        evaluate()
    }

    private func evaluate() {
        let info = ProcessInfo.processInfo
        let previous = level
        let previousConditions = conditions
        conditions = QualityConditions(
            thermal: QualityConditions.Thermal(info.thermalState),
            lowPowerMode: info.isLowPowerModeEnabled,
            sustainedFrameDrops: drops.isSustained
        )
        level = governor.update(conditions, enabled: enabled, now: info.systemUptime)
        guard level != previous || conditions != previousConditions else { return }
        if level != previous { logLevelChange(from: previous) }
        onChange?(level, conditions)
    }

    private func logLevelChange(from previous: QualityLevel) {
        let info = ProcessInfo.processInfo
        logger.notice("품질 단계 \(previous.rawValue) → \(self.level.rawValue) (발열 \(info.thermalState.rawValue), 저전력 \(info.isLowPowerModeEnabled), 누락 지속 \(self.drops.isSustained))")
    }
}

private extension QualityConditions.Thermal {
    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }
}
