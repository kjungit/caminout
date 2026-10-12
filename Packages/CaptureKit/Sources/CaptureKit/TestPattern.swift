import CoreGraphics
import CoreImage
import CoreVideo

/// 검증용 테스트 화면 (검증 계획 4장 B7 색 정확도).
public enum TestPattern {

    /// 75% 색 막대 8개 (흰·노랑·청록·초록·자홍·빨강·파랑·검정). sRGB 8비트 값.
    public static let colorBarValues: [(r: UInt8, g: UInt8, b: UInt8)] = [
        (191, 191, 191), (191, 191, 0), (0, 191, 191), (0, 191, 0),
        (191, 0, 191), (191, 0, 0), (0, 0, 191), (0, 0, 0),
    ]

    /// 색 막대 BGRA 픽셀 버퍼.
    public static func colorBars(width: Int = 1920, height: Int = 1080) -> CVPixelBuffer? {
        guard let buffer = makeBGRABuffer(width: width, height: height) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let count = colorBarValues.count
        for x in 0..<width {
            let bar = colorBarValues[min(x * count / width, count - 1)]
            for y in 0..<height {
                let p = base + y * bytesPerRow + x * 4
                p[0] = bar.b; p[1] = bar.g; p[2] = bar.r; p[3] = 255
            }
        }
        tagSRGB(buffer)
        return buffer
    }

    /// 이미지 파일을 BGRA 픽셀 버퍼로 읽는다.
    public static func pixelBuffer(contentsOf url: URL, context: CIContext = CIContext()) -> CVPixelBuffer? {
        guard let image = CIImage(contentsOf: url) else { return nil }
        let extent = image.extent.integral
        let normalized = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        guard let buffer = makeBGRABuffer(width: Int(extent.width), height: Int(extent.height)) else { return nil }
        context.render(normalized, to: buffer, bounds: CGRect(origin: .zero, size: extent.size), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        tagSRGB(buffer)
        return buffer
    }

    static func makeBGRABuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        return buffer
    }

    private static func tagSRGB(_ buffer: CVPixelBuffer) {
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
    }
}
