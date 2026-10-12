import CamZoomCore
import CoreMedia
import CoreVideo
import XCTest
@testable import EffectsKit

/// 고정 입력 이미지를 합성해 위치별 색을 확인하는 스냅샷 성격의 테스트 (설계서 11장).
/// GPU·macOS 버전에 따라 색이 미세하게 달라지므로 "어느 색 계열인지"만 비교한다.
final class CompositorTests: XCTestCase {

    private enum Tint: Equatable { case red, blue, green, black, other }
    private let compositor = Compositor()

    /// 좌상단 원점 기준으로 색을 정해 BGRA 버퍼를 만든다.
    private func makeSource(width: Int, height: Int, color: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &buffer)
        let pb = buffer!
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = color(x, y)
                let p = base + y * bpr + x * 4
                p[0] = b; p[1] = g; p[2] = r; p[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        return pb
    }

    /// 좌상단 원점 기준 위치의 색 계열.
    private func tint(_ buffer: CVPixelBuffer, x: Int, y: Int) -> Tint {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let p = base + y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
        let (b, g, r) = (Int(p[0]), Int(p[1]), Int(p[2]))
        if r > 180, g < 80, b < 80 { return .red }
        if b > 180, r < 80, g < 80 { return .blue }
        if g > 180, r < 80, b < 80 { return .green }
        if r < 20, g < 20, b < 20 { return .black }
        return .other
    }

    /// 왼쪽 절반 빨강, 오른쪽 절반 파랑.
    private lazy var leftRedRightBlue = makeSource(width: 640, height: 360) { x, _ in
        x < 320 ? (255, 0, 0) : (0, 0, 255)
    }

    /// 위쪽 절반 빨강, 아래쪽 절반 파랑.
    private lazy var topRedBottomBlue = makeSource(width: 640, height: 360) { _, y in
        y < 180 ? (255, 0, 0) : (0, 0, 255)
    }

    private func render(_ source: CVPixelBuffer, _ config: PipelineConfig, frame: UInt64 = 0) throws -> CVPixelBuffer {
        try XCTUnwrap(compositor.render(source, config: config, time: .zero, frameIndex: frame))
    }

    func testOutputHasRequestedSize() throws {
        let out = try render(leftRedRightBlue, PipelineConfig(outputSize: CGSize(width: 1280, height: 720)))
        XCTAssertEqual(CVPixelBufferGetWidth(out), 1280)
        XCTAssertEqual(CVPixelBufferGetHeight(out), 720)
    }

    func testDefaultPassesThroughLayout() throws {
        let out = try render(leftRedRightBlue, PipelineConfig())
        XCTAssertEqual(tint(out, x: 100, y: 540), .red)
        XCTAssertEqual(tint(out, x: 1800, y: 540), .blue)
    }

    func testZoomOnLeftHalfShowsOnlyRed() throws {
        let config = PipelineConfig(crop: CropState(zoom: 2, centerX: 0.25, centerY: 0.5))
        let out = try render(leftRedRightBlue, config)
        XCTAssertEqual(tint(out, x: 20, y: 540), .red)
        XCTAssertEqual(tint(out, x: 1900, y: 540), .red)
    }

    func testZoomOnTopHalfShowsOnlyRedVertically() throws {
        let config = PipelineConfig(crop: CropState(zoom: 2, centerX: 0.5, centerY: 0.25))
        let out = try render(topRedBottomBlue, config)
        XCTAssertEqual(tint(out, x: 960, y: 20), .red)
        XCTAssertEqual(tint(out, x: 960, y: 1060), .red)
    }

    func testMirrorSwapsSides() throws {
        let out = try render(leftRedRightBlue, PipelineConfig(crop: CropState(mirrored: true)))
        XCTAssertEqual(tint(out, x: 100, y: 540), .blue)
        XCTAssertEqual(tint(out, x: 1800, y: 540), .red)
    }

    func testRotateRightMovesTopToRight() throws {
        // 90도 회전하면 세로 화면이 되어 16:9 안에 가운데 배치된다. 위쪽(빨강)이 오른쪽으로 간다.
        let out = try render(topRedBottomBlue, PipelineConfig(crop: CropState(rotation: .right)))
        XCTAssertEqual(tint(out, x: 960 + 200, y: 540), .red)
        XCTAssertEqual(tint(out, x: 960 - 200, y: 540), .blue)
        XCTAssertEqual(tint(out, x: 10, y: 540), .black)
    }

    func testSquareIsCenteredWithBarsInSixteenNine() throws {
        let out = try render(leftRedRightBlue, PipelineConfig(crop: CropState(aspect: .square)))
        XCTAssertEqual(tint(out, x: 100, y: 540), .black)
        XCTAssertEqual(tint(out, x: 1820, y: 540), .black)
        XCTAssertEqual(tint(out, x: 700, y: 540), .red)
        XCTAssertEqual(tint(out, x: 1220, y: 540), .blue)
    }

    func testSquareFillHasNoBars() throws {
        let config = PipelineConfig(crop: CropState(aspect: .square), fitMode: .fill)
        let out = try render(leftRedRightBlue, config)
        XCTAssertEqual(tint(out, x: 5, y: 540), .red)
        XCTAssertEqual(tint(out, x: 1915, y: 540), .blue)
    }

    func testEffectsDisabledIgnoresCrop() throws {
        let config = PipelineConfig(crop: CropState(zoom: 3, centerX: 0.1, mirrored: true), effectsEnabled: false)
        let out = try render(leftRedRightBlue, config)
        XCTAssertEqual(tint(out, x: 100, y: 540), .red)
        XCTAssertEqual(tint(out, x: 1800, y: 540), .blue)
    }

    func testFrameNumberDrawsOnlyWhenEnabled() throws {
        let green = makeSource(width: 640, height: 360) { _, _ in (0, 255, 0) }
        let plain = try render(green, PipelineConfig())
        XCTAssertEqual(tint(plain, x: 40, y: 40), .green)

        let numbered = try render(green, PipelineConfig(showFrameNumber: true), frame: 42)
        XCTAssertNotEqual(tint(numbered, x: 40, y: 40), .green)
        XCTAssertEqual(tint(numbered, x: 960, y: 900), .green)
    }

    func testThumbnailIsOrientedAndScaled() throws {
        let thumb = try XCTUnwrap(compositor.thumbnail(
            of: leftRedRightBlue, crop: CropState(rotation: .right), maxWidth: 180
        ))
        XCTAssertEqual(thumb.width, 180)
        XCTAssertEqual(thumb.height, 320)
    }
}

final class FrameGeometryTests: XCTestCase {

    func testSourceToOutputMapsCropCenterToPlacementCenter() {
        let config = PipelineConfig(crop: CropState(zoom: 2, centerX: 0.25, centerY: 0.25))
        let g = FrameGeometry(sourceSize: CGSize(width: 1920, height: 1080), config: config)
        // 좌상단 기준 (480, 270)은 Core Image 좌표로 (480, 810).
        let mapped = CGPoint(x: 480, y: 810).applying(g.sourceToOutputTransform)
        XCTAssertEqual(mapped.x, 960, accuracy: 0.5)
        XCTAssertEqual(mapped.y, 540, accuracy: 0.5)
    }

    func testRotationGeometrySwapsOrientedSize() {
        let config = PipelineConfig(crop: CropState(rotation: .left))
        let g = FrameGeometry(sourceSize: CGSize(width: 1920, height: 1080), config: config)
        XCTAssertEqual(g.orientedSize, CGSize(width: 1080, height: 1920))
        let corner = CGRect(origin: .zero, size: g.sourceSize).applying(g.orientationTransform)
        XCTAssertEqual(corner.origin, .zero)
        XCTAssertEqual(corner.size, g.orientedSize)
    }
}
