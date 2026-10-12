import CamZoomCore
import CoreGraphics

/// 한 프레임의 좌표 계산 결과. 자르기(1번 레이어)와 출력 맞춤(9번 레이어)이 같은 값을 쓴다.
///
/// Core Image는 좌하단 원점이고 CropMath는 좌상단 원점이다. 변환은 여기서만 한다.
public struct FrameGeometry: Equatable, Sendable {
    public let sourceSize: CGSize
    /// 반전·회전 뒤 크기.
    public let orientedSize: CGSize
    /// 반전·회전 뒤 화면에서 잘라낼 영역 (좌상단 원점).
    public let cropRect: CGRect
    public let outputSize: CGSize
    /// 출력 화면 안에서 자른 화면이 놓일 영역 (좌상단 원점).
    public let placement: CGRect
    /// 원본(Core Image 좌표) → 반전·회전 뒤 화면(Core Image 좌표).
    public let orientationTransform: CGAffineTransform
    /// 반전·회전 뒤 화면 → 출력 화면 (둘 다 Core Image 좌표).
    public let cropToOutputTransform: CGAffineTransform

    /// 원본 → 출력. 얼굴 좌표를 출력 화면 위치로 옮길 때 쓴다 (설계서 7.2).
    public var sourceToOutputTransform: CGAffineTransform {
        orientationTransform.concatenating(cropToOutputTransform)
    }

    public init(sourceSize: CGSize, config: PipelineConfig) {
        let state = config.effectsEnabled ? config.crop.sanitized : CropState()
        self.sourceSize = sourceSize
        self.outputSize = config.outputSize
        self.orientationTransform = Self.orientation(sourceSize: sourceSize, state: state)
        self.orientedSize = CropMath.orientedSize(source: sourceSize, rotation: state.rotation)
        self.cropRect = CropMath.cropRect(source: orientedSize, state: state)
        self.placement = CropMath.placement(content: cropRect.size, output: outputSize, mode: config.fitMode)

        // 잘라낼 영역을 원점으로 옮긴 뒤, 출력 안의 놓일 자리 크기로 늘리고 옮긴다.
        let ciCropOrigin = CGPoint(x: cropRect.minX, y: orientedSize.height - cropRect.maxY)
        let scale = cropRect.width > 0 ? placement.width / cropRect.width : 1
        let ciPlacementOrigin = CGPoint(x: placement.minX, y: outputSize.height - placement.maxY)
        self.cropToOutputTransform = CGAffineTransform(translationX: -ciCropOrigin.x, y: -ciCropOrigin.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: ciPlacementOrigin.x, y: ciPlacementOrigin.y))
    }

    /// 출력 화면 안에서 자른 화면이 보이는 영역 (Core Image 좌표).
    public var ciVisibleRect: CGRect {
        let output = CGRect(origin: .zero, size: outputSize)
        let placed = CGRect(
            x: placement.minX, y: outputSize.height - placement.maxY,
            width: placement.width, height: placement.height
        )
        return placed.intersection(output)
    }

    /// 좌우 반전 후 시계 방향 회전. 결과 화면의 원점은 (0, 0)이다.
    private static func orientation(sourceSize: CGSize, state: CropState) -> CGAffineTransform {
        let w = sourceSize.width
        let h = sourceSize.height
        var t = CGAffineTransform.identity
        if state.mirrored {
            t = t.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))
        }
        // Core Image는 y가 위로 증가하므로 시계 방향 90도는 (x, y) → (y, w - x).
        switch state.rotation {
        case .none:
            break
        case .right:
            t = t.concatenating(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w))
        case .upsideDown:
            t = t.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h))
        case .left:
            t = t.concatenating(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0))
        }
        return t
    }
}
