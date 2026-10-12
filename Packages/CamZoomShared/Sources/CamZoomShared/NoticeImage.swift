import CoreGraphics
import CoreText
import CoreVideo
import Foundation

/// 호스트 앱이 꺼져 있을 때 가상 카메라가 대신 내보내는 안내 화면 (설계서 6장, A5).
/// 화상 앱 화면 크기가 바뀌지 않도록 현재 출력 형식과 같은 크기로 만든다.
public enum NoticeImage {

    public static let title = "\(CameraIdentity.productName) 앱을 실행해 주세요"
    public static let subtitle = "앱이 꺼져 있어서 카메라 화면을 보낼 수 없어요"

    /// 안내 화면을 그린 픽셀 버퍼를 만든다. 실패하면 nil.
    public static func makePixelBuffer(format: OutputFormat) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(format.width),
            Int(format.height),
            OutputFormat.pixelFormat,
            format.pixelBufferAttributes() as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }
        draw(into: buffer)
        OutputFormat.applyColorAttachments(to: buffer)
        return buffer
    }

    /// BGRA 픽셀 버퍼에 안내 화면을 그린다.
    public static func draw(into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard
            let base = CVPixelBufferGetBaseAddress(buffer),
            let colorSpace = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { return }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
        context.fill(rect)

        // 카메라 아이콘 대신 강조색 원 하나 (다크 모드 강조색 #FF8A66).
        let unit = CGFloat(min(width, height))
        let dot = unit * 0.12
        context.setFillColor(CGColor(red: 1.0, green: 0.541, blue: 0.4, alpha: 1))
        context.fillEllipse(in: CGRect(x: rect.midX - dot / 2, y: rect.midY + unit * 0.08, width: dot, height: dot))

        drawCentered(title, in: context, size: unit * 0.055, y: rect.midY - unit * 0.02, width: rect.width, gray: 0.96, bold: true)
        drawCentered(subtitle, in: context, size: unit * 0.032, y: rect.midY - unit * 0.10, width: rect.width, gray: 0.62, bold: false)
    }

    private static func drawCentered(
        _ text: String, in context: CGContext, size: CGFloat, y: CGFloat, width: CGFloat, gray: CGFloat, bold: Bool
    ) {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, "ko" as CFString)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.textPosition = CGPoint(x: (width - bounds.width) / 2 - bounds.minX, y: y)
        CTLineDraw(line, context)
    }
}
