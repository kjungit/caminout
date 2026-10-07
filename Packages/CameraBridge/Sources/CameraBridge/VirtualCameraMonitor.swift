import CamZoomShared
import CoreMediaIO
import Foundation
import os

/// 가상 카메라의 현재 상태. 익스텐션이 사용자 정의 속성으로 알려 준 값이다 (설계서 6장, G3·G5).
public struct VirtualCameraStatus: Equatable, Sendable {
    /// 시스템에 가상 카메라 장치가 보이는지.
    public var installed: Bool = false
    /// 익스텐션이 알려 준 "화상 앱이 source를 쓰는 중" 값. 속성이 없으면 nil.
    public var sourceActive: Bool?
    /// 장치 기본 속성 kCMIODevicePropertyDeviceIsRunningSomewhere. A4 비교용.
    public var runningSomewhere: Bool = false
    public var protocolVersion: Int?
    public var activeFormat: OutputFormat?
    public var extensionBuild: String?

    public init() {}

    /// 화상 앱이 가상 카메라를 쓰고 있는지. 사용자 정의 속성을 우선한다.
    /// 장치 기본 속성은 앱 자신이 sink를 열어도 켜지므로 보조로만 쓴다.
    public var inUse: Bool { sourceActive ?? false }

    /// 앱과 익스텐션 프로토콜이 다른지 (G5). 버전을 알 수 없으면 false.
    public var versionMismatch: Bool {
        guard installed, let protocolVersion else { return false }
        return protocolVersion != CameraIdentity.protocolVersion
    }
}

/// 가상 카메라 상태를 주기적으로 읽고 바뀌면 알린다.
/// 속성 변경 알림은 환경에 따라 오지 않을 수 있어 0.5초 간격 확인을 기본으로 한다.
public final class VirtualCameraMonitor: @unchecked Sendable {

    public let interval: TimeInterval
    private let queue = DispatchQueue(label: "com.kjungit.caminout.camera-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var last: VirtualCameraStatus?
    private let logger = Logger(subsystem: "com.kjungit.caminout", category: "monitor")

    public init(interval: TimeInterval = 0.5) {
        self.interval = interval
    }

    public func start(onChange: @escaping @Sendable (VirtualCameraStatus) -> Void) {
        queue.async { [self] in
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: interval)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let status = Self.read()
                if status != self.last {
                    self.logChange(from: self.last, to: status)
                    self.last = status
                    onChange(status)
                }
            }
            self.timer = timer
            timer.resume()
        }
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            last = nil
        }
    }

    /// 지금 상태를 한 번 읽는다.
    public static func read() -> VirtualCameraStatus {
        var status = VirtualCameraStatus()
        guard let device = VirtualCameraLocator.find() else { return status }
        status.installed = true
        let id = device.deviceID
        status.runningSomewhere = (CMIOProperty.uint32(id, UInt32(kCMIODevicePropertyDeviceIsRunningSomewhere)) ?? 0) != 0
        if let value = CMIOProperty.string(id, CustomProperty.sourceActive.selector) {
            status.sourceActive = value == "1"
        }
        status.protocolVersion = CMIOProperty.string(id, CustomProperty.protocolVersion.selector).flatMap { Int($0) }
        status.activeFormat = CMIOProperty.string(id, CustomProperty.activeFormat.selector).flatMap(OutputFormat.init(string:))
        status.extensionBuild = CMIOProperty.string(id, CustomProperty.extensionBuild.selector)
        return status
    }

    private func logChange(from old: VirtualCameraStatus?, to new: VirtualCameraStatus) {
        logger.info("""
        가상 카메라 상태: installed=\(new.installed) sourceActive=\(String(describing: new.sourceActive), privacy: .public) \
        runningSomewhere=\(new.runningSomewhere) protocol=\(String(describing: new.protocolVersion), privacy: .public) \
        format=\(new.activeFormat?.description ?? "-", privacy: .public) build=\(new.extensionBuild ?? "-", privacy: .public)
        """)
    }
}
