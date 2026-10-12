import CamZoomCore
import CoreImage
import CoreMedia
import CoreVideo
import Metal
import os

/// 레이어 목록으로 CIImage 그래프 하나를 만들고, 마지막에 한 번만 GPU 렌더링한다 (설계서 7장).
///
/// renderQueue 하나에서만 호출한다 (설계서 9.1). 그래서 내부 상태에 잠금을 두지 않는다.
public final class Compositor: @unchecked Sendable {

    /// 출력 버퍼 풀 최소 크기. 화상 앱이 버퍼를 붙잡아 둬서 풀이 바닥나는 사례 때문에 넉넉히 잡는다 (설계서 5장).
    public static let minimumPoolBufferCount = 8
    /// 풀이 이 개수를 넘게 할당하려 하면 개별 할당으로 넘어가고 기록한다.
    public static let poolAllocationThreshold = 16

    public let ciContext: CIContext
    public let outputColorSpace: CGColorSpace
    private var layers: [any EffectLayer]

    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero
    private let logger = Logger(subsystem: "com.kjungit.caminout", category: "compositor")

    /// 풀이 바닥나 개별 할당한 횟수 (B5·B6 측정).
    public private(set) var poolExhaustedCount = 0

    /// - Parameter layers: 추가 레이어. 자르기·출력 맞춤·프레임 번호는 항상 포함된다.
    public init(layers: [any EffectLayer] = [], device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        let colorSpace = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
        let options: [CIContextOption: Any] = [
            .cacheIntermediates: false,
            .outputColorSpace: colorSpace,
            .name: "CamZoom.Compositor",
        ]
        // CIContext는 앱 전체에서 하나만 만들어 재사용한다 (설계서 9.1).
        if let device {
            ciContext = CIContext(mtlDevice: device, options: options)
        } else {
            ciContext = CIContext(options: options)
        }
        outputColorSpace = colorSpace
        self.layers = (layers + [CropLayer(), OutputFitLayer(), FrameNumberLayer()]).sorted { $0.id < $1.id }
    }

    /// 레이어를 합성한 이미지. 렌더링은 하지 않는다.
    public func composedImage(source: CIImage, context: FrameContext) -> CIImage {
        var image = source
        for layer in layers where layer.isEnabled(in: context) {
            if layer.needsFace && context.face == nil { continue }
            image = layer.apply(image, context: context)
        }
        return image
    }

    /// 원본 프레임 하나를 처리해 출력 버퍼를 만든다.
    public func render(
        _ source: CVPixelBuffer,
        config: PipelineConfig,
        time: CMTime,
        frameIndex: UInt64,
        face: FaceFrame? = nil
    ) -> CVPixelBuffer? {
        let input = CIImage(cvPixelBuffer: source)
        let geometry = FrameGeometry(sourceSize: input.extent.size, config: config)
        let context = FrameContext(face: face, time: time, frameIndex: frameIndex, config: config, geometry: geometry)
        let image = composedImage(source: input, context: context)

        guard let output = makeOutputBuffer(size: config.outputSize) else { return nil }
        ciContext.render(
            image, to: output,
            bounds: CGRect(origin: .zero, size: config.outputSize),
            colorSpace: outputColorSpace
        )
        return output
    }

    /// 미리보기용 작은 원본 이미지. 반전·회전은 적용해서 사용자가 보는 방향과 같게 만든다.
    public func thumbnail(of source: CVPixelBuffer, crop: CropState, maxWidth: CGFloat) -> CGImage? {
        let input = CIImage(cvPixelBuffer: source)
        var state = CropState()
        state.mirrored = crop.mirrored
        state.rotation = crop.rotation
        let config = PipelineConfig(crop: state, outputSize: input.extent.size)
        let geometry = FrameGeometry(sourceSize: input.extent.size, config: config)
        let oriented = input.transformed(by: geometry.orientationTransform)
        let scale = min(1, maxWidth / max(oriented.extent.width, 1))
        let small = oriented.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.createCGImage(small, from: small.extent)
    }

    // MARK: - 버퍼 풀

    private func makeOutputBuffer(size: CGSize) -> CVPixelBuffer? {
        if pool == nil || poolSize != size {
            // 크기가 바뀌면 풀을 새로 만든다. 기존 버퍼는 반납될 때까지 그대로 남는다.
            pool = Self.makePool(size: size)
            poolSize = size
        }
        var buffer: CVPixelBuffer?
        if let pool {
            let aux = [kCVPixelBufferPoolAllocationThresholdKey as String: Self.poolAllocationThreshold] as CFDictionary
            let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, aux, &buffer)
            if status == kCVReturnWouldExceedAllocationThreshold {
                poolExhaustedCount += 1
                logger.warning("출력 버퍼 풀 고갈 (\(self.poolExhaustedCount)회), 개별 할당")
                buffer = nil
            }
        }
        if buffer == nil {
            CVPixelBufferCreate(
                kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA,
                Self.bufferAttributes(size: size) as CFDictionary, &buffer
            )
        }
        if let buffer { Self.applyColorAttachments(buffer) }
        return buffer
    }

    private static func bufferAttributes(size: CGSize) -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

    private static func makePool(size: CGSize) -> CVPixelBufferPool? {
        var pool: CVPixelBufferPool?
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: minimumPoolBufferCount] as CFDictionary
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes, bufferAttributes(size: size) as CFDictionary, &pool)
        return pool
    }

    /// 출력은 BT.709로 표시한다 (G7). CamZoomShared.OutputFormat과 같은 규칙이다.
    private static func applyColorAttachments(_ buffer: CVPixelBuffer) {
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    }
}
