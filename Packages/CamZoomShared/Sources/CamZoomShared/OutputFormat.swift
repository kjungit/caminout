import CoreGraphics
import CoreMedia
import CoreVideo

/// 가상 카메라가 화상 앱에 광고하는 출력 형식 (설계서 6장, ADR-10).
public struct OutputFormat: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let width: Int32
    public let height: Int32

    public init(width: Int32, height: Int32) {
        self.width = width
        self.height = height
    }

    public var size: CGSize { CGSize(width: Int(width), height: Int(height)) }
    public var dimensions: CMVideoDimensions { CMVideoDimensions(width: width, height: height) }
    public var description: String { "\(width)x\(height)" }

    /// "1920x1080" 형태 문자열을 해석한다. 익스텐션이 현재 형식을 이 문자열로 알려 준다.
    public init?(string: String) {
        let parts = string.split(separator: "x").compactMap { Int32($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        self.init(width: parts[0], height: parts[1])
    }

    public static let hd720 = OutputFormat(width: 1280, height: 720)
    public static let hd1080 = OutputFormat(width: 1920, height: 1080)
    public static let square1080 = OutputFormat(width: 1080, height: 1080)

    /// 광고 순서. 첫 번째가 기본 형식이다. A3 결과에 따라 문제 형식은 여기서 뺀다.
    public static let advertised: [OutputFormat] = [.hd1080, .hd720, .square1080]
    public static let `default` = OutputFormat.hd1080

    /// 1차는 30fps만 광고한다 (G9).
    public static let frameRate: Int32 = 30
    public static var frameDuration: CMTime { CMTime(value: 1, timescale: frameRate) }

    /// 출력 픽셀 형식. 화상 앱 호환성이 가장 넓다 (설계서 5장).
    public static let pixelFormat: OSType = kCVPixelFormatType_32BGRA

    /// IOSurface 기반 픽셀 버퍼 속성. 미리보기와 sink 큐가 같은 버퍼를 복사 없이 공유한다.
    public func pixelBufferAttributes() -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: OutputFormat.pixelFormat,
            kCVPixelBufferWidthKey as String: Int(width),
            kCVPixelBufferHeightKey as String: Int(height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

    public func makeFormatDescription() -> CMVideoFormatDescription? {
        var description: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: OutputFormat.pixelFormat,
            width: width,
            height: height,
            extensions: OutputFormat.colorExtensions as CFDictionary,
            formatDescriptionOut: &description
        )
        return description
    }

    /// 출력 색 공간은 BT.709로 명시한다. 없으면 화상 앱에서 색이 바래 보일 수 있다 (G7).
    public static var colorExtensions: [String: Any] {
        [
            kCMFormatDescriptionExtension_ColorPrimaries as String: kCMFormatDescriptionColorPrimaries_ITU_R_709_2,
            kCMFormatDescriptionExtension_TransferFunction as String: kCMFormatDescriptionTransferFunction_ITU_R_709_2,
            kCMFormatDescriptionExtension_YCbCrMatrix as String: kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2,
        ]
    }

    /// 픽셀 버퍼에 BT.709 색 정보를 붙인다.
    public static func applyColorAttachments(to buffer: CVPixelBuffer) {
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    }
}
