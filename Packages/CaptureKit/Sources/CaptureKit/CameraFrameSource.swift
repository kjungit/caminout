@preconcurrency import AVFoundation
import os

/// 고를 수 있는 입력 카메라 하나.
public struct CameraDeviceInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
}

public enum CameraDevices {
    /// 입력 카메라 목록. 자기 가상 카메라는 빼서 영상 되먹임을 막는다 (기획서 5.1).
    public static func available(excludingIDs: Set<String> = [], excludingNames: Set<String> = []) -> [CameraDeviceInfo] {
        discoverySession().devices
            .filter { !excludingIDs.contains($0.uniqueID) && !excludingNames.contains($0.localizedName) }
            .map { CameraDeviceInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func discoverySession() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
    }

    static func device(id: String?, excludingIDs: Set<String>, excludingNames: Set<String>) -> AVCaptureDevice? {
        let candidates = discoverySession().devices
            .filter { !excludingIDs.contains($0.uniqueID) && !excludingNames.contains($0.localizedName) }
        if let id, let match = candidates.first(where: { $0.uniqueID == id }) {
            return match
        }
        // 고른 카메라가 없으면 내장 카메라, 그것도 없으면 첫 번째.
        return candidates.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? candidates.first
    }
}

public enum CameraAuthorization {
    public static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// 권한을 확인하고, 아직 묻지 않았으면 묻는다.
    public static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

/// AVFoundation 카메라 입력 (설계서 5장 1단계 캡처).
///
/// 입력 형식은 카메라 기본 형식인 420YpCbCr8BiPlanarFullRange로 받는다. 변환 비용이 없고 Vision도 그대로 받는다.
/// 모든 상태는 captureQueue에서만 바꾼다.
public final class CameraFrameSource: NSObject, FrameSource, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    public let deviceID: String?
    private let excludingIDs: Set<String>
    private let excludingNames: Set<String>
    private let queue: DispatchQueue
    private let session = AVCaptureSession()
    private var onFrame: (@Sendable (CapturedFrame) -> Void)?
    private var onError: (@Sendable (CaptureError) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var currentDevice: AVCaptureDevice?
    private let logger = Logger(subsystem: "com.kjungit.caminout", category: "capture")

    /// 현재 열린 카메라 이름. 진단용.
    public private(set) var activeDeviceName: String?

    public init(deviceID: String?, excludingIDs: Set<String> = [], excludingNames: Set<String> = [], queue: DispatchQueue) {
        self.deviceID = deviceID
        self.excludingIDs = excludingIDs
        self.excludingNames = excludingNames
        self.queue = queue
        super.init()
    }

    public func start(onFrame: @escaping @Sendable (CapturedFrame) -> Void, onError: @escaping @Sendable (CaptureError) -> Void) {
        queue.async { [self] in
            self.onFrame = onFrame
            self.onError = onError
            guard CameraAuthorization.isAuthorized else {
                onError(.permissionDenied)
                return
            }
            do {
                try configure()
                observe()
                session.startRunning()
            } catch let error as CaptureError {
                onError(error)
            } catch {
                onError(.cannotOpen(error.localizedDescription))
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            session.stopRunning()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            onFrame = nil
            onError = nil
        }
    }

    private func configure() throws {
        guard let device = CameraDevices.device(id: deviceID, excludingIDs: excludingIDs, excludingNames: excludingNames) else {
            throw CaptureError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)

        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        guard session.canAddInput(input) else { throw CaptureError.cannotOpen(device.localizedName) }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        // 늦은 프레임을 쌓아 지연을 키우는 것보다 버리는 편이 낫다 (설계서 5장).
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CaptureError.cannotOpen(device.localizedName) }
        session.addOutput(output)

        currentDevice = device
        activeDeviceName = device.localizedName
        logger.info("카메라 열림: \(device.localizedName, privacy: .public) \(device.uniqueID, privacy: .public)")
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let self, let device = note.object as? AVCaptureDevice else { return }
            let id = device.uniqueID
            let name = device.localizedName
            self.queue.async { self.handleDisconnect(id: id, name: name) }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { [weak self] note in
            guard let self else { return }
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            let detail = error?.localizedDescription ?? "알 수 없는 오류"
            self.queue.async { self.handleRuntimeError(detail) }
        })
    }

    /// 쓰던 카메라가 빠지면 다른 카메라로 넘어간다. 없으면 오류를 알린다.
    private func handleDisconnect(id: String, name: String) {
        guard id == currentDevice?.uniqueID else { return }
        logger.warning("카메라 분리: \(name, privacy: .public)")
        session.stopRunning()
        do {
            try configure()
            session.startRunning()
        } catch {
            onError?(.disconnected(name))
        }
    }

    /// 잠자기 복귀 등으로 세션이 멈추면 한 번 다시 시작한다.
    private func handleRuntimeError(_ detail: String) {
        logger.error("캡처 세션 오류: \(detail, privacy: .public)")
        if onFrame != nil {
            session.startRunning()
            if !session.isRunning { onError?(.runtime(detail)) }
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // 화상 앱 출력 타임스탬프는 호스트 시간 기준이어야 하므로 캡처 시각을 그대로 쓴다 (G10).
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrame?(CapturedFrame(pixelBuffer: pixelBuffer, time: time.isValid ? time : HostClock.now()))
    }
}
