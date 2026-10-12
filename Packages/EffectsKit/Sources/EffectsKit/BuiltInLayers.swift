import CamZoomCore
import CoreImage
import CoreImage.CIFilterBuiltins

/// 1번 레이어: 반전·회전 후 확대 위치·배율·비율대로 자른다.
/// 결과는 자른 화면이 출력 화면 안의 놓일 자리에 이미 옮겨진 상태다 (좌표 변환을 한 번에 하기 위해서).
public struct CropLayer: EffectLayer {
    public let id = LayerID.crop
    public init() {}

    public func isEnabled(in context: FrameContext) -> Bool { true }

    public func apply(_ image: CIImage, context: FrameContext) -> CIImage {
        let g = context.geometry
        let oriented = image.transformed(by: g.orientationTransform)
        let ciCrop = CGRect(
            x: g.cropRect.minX, y: g.orientedSize.height - g.cropRect.maxY,
            width: g.cropRect.width, height: g.cropRect.height
        )
        return oriented
            .clampedToExtent()
            .cropped(to: ciCrop)
            .transformed(by: g.cropToOutputTransform)
            .cropped(to: g.ciVisibleRect)
    }
}

/// 9번 레이어: 출력 형식 크기로 맞추고 남는 곳을 검은색으로 채운다 (16:9 안 정사각형 가운데 배치).
public struct OutputFitLayer: EffectLayer {
    public let id = LayerID.outputFit
    public init() {}

    public func isEnabled(in context: FrameContext) -> Bool { true }

    public func apply(_ image: CIImage, context: FrameContext) -> CIImage {
        let canvas = CGRect(origin: .zero, size: context.outputSize)
        return image
            .composited(over: CIImage(color: .black).cropped(to: canvas))
            .cropped(to: canvas)
    }
}

/// 검증용 프레임 번호 표시 (검증 계획 4장 "FPS·누락"). QuickTime으로 녹화해 빠진 번호를 센다.
public struct FrameNumberLayer: EffectLayer {
    public let id = LayerID.debug
    public init() {}

    public func isEnabled(in context: FrameContext) -> Bool { context.config.showFrameNumber }

    public func apply(_ image: CIImage, context: FrameContext) -> CIImage {
        let height = context.outputSize.height
        let fontSize = max(24, height * 0.07)
        let generator = CIFilter.textImageGenerator()
        generator.text = String(format: "%06llu", context.frameIndex)
        generator.fontName = "Menlo-Bold"
        generator.fontSize = Float(fontSize)
        generator.scaleFactor = 1
        guard let text = generator.outputImage else { return image }

        let margin = fontSize * 0.4
        let box = CGRect(
            x: margin, y: height - margin - text.extent.height - margin,
            width: text.extent.width + margin * 2, height: text.extent.height + margin
        )
        let placedText = text.transformed(by: CGAffineTransform(
            translationX: box.minX + margin - text.extent.minX, y: box.minY + margin / 2 - text.extent.minY
        ))
        let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.75)).cropped(to: box)
        return placedText.composited(over: background.composited(over: image))
    }
}
