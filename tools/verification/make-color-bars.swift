// 색 막대 PNG 생성 (검증 계획 4장 B7 색 정확도).
// 앱의 "색 막대 (검증용)" 입력과 같은 75% 막대 8개를 sRGB PNG로 저장한다.
// 사용법: swift tools/verification/make-color-bars.swift [출력 경로] [가로] [세로]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let output = args.count > 1 ? args[1] : "color-bars.png"
let width = args.count > 2 ? Int(args[2]) ?? 1920 : 1920
let height = args.count > 3 ? Int(args[3]) ?? 1080 : 1080

// CaptureKit.TestPattern.colorBarValues 와 같은 값.
let bars: [(UInt8, UInt8, UInt8)] = [
    (191, 191, 191), (191, 191, 0), (0, 191, 191), (0, 191, 0),
    (191, 0, 191), (191, 0, 0), (0, 0, 191), (0, 0, 0),
]

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("context") }

for (index, bar) in bars.enumerated() {
    let x0 = index * width / bars.count
    let x1 = (index + 1) * width / bars.count
    context.setFillColor(red: CGFloat(bar.0) / 255, green: CGFloat(bar.1) / 255, blue: CGFloat(bar.2) / 255, alpha: 1)
    context.fill(CGRect(x: x0, y: 0, width: x1 - x0, height: height))
}

let url = URL(fileURLWithPath: output)
guard
    let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("image") }
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("저장: \(url.path) (\(width)x\(height))")
print("막대 값 (R,G,B):")
for bar in bars { print("  \(bar.0), \(bar.1), \(bar.2)") }
