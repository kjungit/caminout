import CoreImage
import CoreGraphics

/// 카메라 프레임 한 장을 CropState에 따라 잘라서 확대하는 처리기.
/// 앱의 미리보기와 카메라 익스텐션의 실제 출력이 동일한 결과를 내도록
/// 이 로직 하나만 공유한다 (기획서 9.1 CamZoomCore 역할).
public enum FrameProcessor {

    public struct Result {
        public let image: CIImage
        public let size: CGSize
    }

    /// - Parameters:
    ///   - image: 원본 카메라 프레임 (좌상단 원점 기준으로 다룬다)
    ///   - state: 확대·위치·비율 설정
    /// - Returns: 잘라서 확대한 이미지와 그 출력 크기
    public static func process(_ image: CIImage, state: CropState) -> Result {
        let sourceSize = image.extent.size
        let rect = CropMath.cropRect(source: sourceSize, state: state)
        let outputSize = CropMath.outputSize(for: rect)

        // Core Image는 좌하단 원점을 쓰므로 y 좌표를 뒤집어 변환한다.
        let ciRect = CGRect(
            x: rect.minX,
            y: sourceSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        guard rect.width > 0, rect.height > 0 else {
            return Result(image: image, size: sourceSize)
        }

        let scaleX = outputSize.width / rect.width
        let scaleY = outputSize.height / rect.height

        let processed = image
            .clampedToExtent()
            .cropped(to: ciRect)
            .transformed(by: CGAffineTransform(translationX: -ciRect.minX, y: -ciRect.minY))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: outputSize))

        return Result(image: processed, size: outputSize)
    }
}
