import CoreMedia
import CoreVideo

/// 캡처된 프레임 하나. 큐 사이에는 이 값만 넘긴다 (설계서 9장).
/// 픽셀 버퍼는 읽기 전용으로만 다루므로 큐 사이를 넘겨도 안전하다.
public struct CapturedFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    /// 호스트 시간 기준 캡처 시각.
    public let time: CMTime

    public init(pixelBuffer: CVPixelBuffer, time: CMTime) {
        self.pixelBuffer = pixelBuffer
        self.time = time
    }
}

public enum CaptureError: Error, Equatable, Sendable {
    case permissionDenied
    case noCamera
    case cannotOpen(String)
    case disconnected(String)
    case runtime(String)
    case cannotReadFile(String)

    /// 사용자에게 보여줄 문구 (기획서 10장 예외 처리).
    public var message: String {
        switch self {
        case .permissionDenied:
            return "카메라 권한이 필요합니다. 시스템 설정 > 개인정보 보호 및 보안 > 카메라에서 허용해 주세요."
        case .noCamera:
            return "카메라를 찾을 수 없습니다."
        case .cannotOpen(let detail):
            return "카메라를 열 수 없습니다: \(detail)"
        case .disconnected(let name):
            return "\(name) 연결이 끊어졌습니다. 다른 카메라로 바꾸거나 다시 연결해 주세요."
        case .runtime(let detail):
            return "카메라 오류가 발생했습니다: \(detail)"
        case .cannotReadFile(let path):
            return "입력 파일을 읽을 수 없습니다: \(path)"
        }
    }
}

/// 실제 카메라와 가짜 입력이 같이 따르는 인터페이스.
/// 자동 테스트와 측정이 실제 카메라에 의존하지 않도록 캡처 단계를 바꿔 끼울 수 있게 한다 (설계서 11장).
public protocol FrameSource: AnyObject, Sendable {
    /// 캡처를 시작한다. 프레임은 생성 시 받은 큐에서 `onFrame`으로 전달된다.
    func start(onFrame: @escaping @Sendable (CapturedFrame) -> Void, onError: @escaping @Sendable (CaptureError) -> Void)
    func stop()
}

public enum HostClock {
    /// 호스트 시간 기준 현재 시각.
    public static func now() -> CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
    }
}
