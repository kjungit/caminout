import CoreGraphics

/// 한 프레임의 얼굴 추적 결과 (설계서 7.3). 3단계부터 FaceTracking 패키지가 채운다.
/// 좌표는 원본 프레임 기준 0~1이다. 자르기 뒤의 레이어는 FrameContext.cropTransform으로 변환해서 쓴다.
public struct FaceFrame: Equatable, Sendable {
    public struct HeadPose: Equatable, Sendable {
        public var roll: Double
        public var yaw: Double
        public var pitch: Double

        public init(roll: Double = 0, yaw: Double = 0, pitch: Double = 0) {
            self.roll = roll
            self.yaw = yaw
            self.pitch = pitch
        }
    }

    public var boundingBox: CGRect
    public var landmarks: [CGPoint]
    public var headPose: HeadPose
    public var eyeOpenLeft: Double
    public var eyeOpenRight: Double
    public var mouthOpen: Double
    /// 52개 표정 계수. Vision 출처일 때는 비어 있다.
    public var blendshapes: [String: Double]
    public var confidence: Double

    public init(
        boundingBox: CGRect,
        landmarks: [CGPoint] = [],
        headPose: HeadPose = HeadPose(),
        eyeOpenLeft: Double = 1,
        eyeOpenRight: Double = 1,
        mouthOpen: Double = 0,
        blendshapes: [String: Double] = [:],
        confidence: Double = 1
    ) {
        self.boundingBox = boundingBox
        self.landmarks = landmarks
        self.headPose = headPose
        self.eyeOpenLeft = eyeOpenLeft
        self.eyeOpenRight = eyeOpenRight
        self.mouthOpen = mouthOpen
        self.blendshapes = blendshapes
        self.confidence = confidence
    }
}
