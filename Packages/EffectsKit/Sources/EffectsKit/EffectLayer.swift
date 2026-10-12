import CamZoomCore
import CoreImage
import CoreMedia

/// 레이어 쌓는 순서 (설계서 7.1). 숫자가 작을수록 먼저 적용된다.
public enum LayerID: Int, Comparable, Sendable {
    case crop = 1
    case background = 2
    case faceDistortion = 3
    case character = 4
    case colorFilter = 5
    case faceSticker = 6
    case overlay = 7
    case frame = 8
    case outputFit = 9
    /// 개발·검증용 표시 (프레임 번호). 항상 맨 위.
    case debug = 100

    public static func < (lhs: LayerID, rhs: LayerID) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 레이어가 한 프레임을 처리할 때 받는 정보 (설계서 7.2).
public struct FrameContext: Sendable {
    /// 최근 추적 결과, 없으면 nil.
    public let face: FaceFrame?
    /// 출력 타임스탬프.
    public let time: CMTime
    /// 개발용 프레임 번호 (누락 측정).
    public let frameIndex: UInt64
    public let config: PipelineConfig
    public let geometry: FrameGeometry

    /// 화상 앱이 고른 출력 형식.
    public var outputSize: CGSize { geometry.outputSize }
    /// 원본 좌표 → 출력 화면 좌표. 확대해도 스티커가 얼굴에서 벗어나지 않게 하는 데 쓴다.
    public var cropTransform: CGAffineTransform { geometry.sourceToOutputTransform }

    public init(face: FaceFrame?, time: CMTime, frameIndex: UInt64, config: PipelineConfig, geometry: FrameGeometry) {
        self.face = face
        self.time = time
        self.frameIndex = frameIndex
        self.config = config
        self.geometry = geometry
    }
}

/// 모든 효과가 따르는 인터페이스. 새 효과는 레이어 하나를 추가하는 것으로 끝난다 (설계 원칙 4).
public protocol EffectLayer: Sendable {
    var id: LayerID { get }
    func isEnabled(in context: FrameContext) -> Bool
    var needsFace: Bool { get }
    func apply(_ image: CIImage, context: FrameContext) -> CIImage
}

public extension EffectLayer {
    var needsFace: Bool { false }
}
