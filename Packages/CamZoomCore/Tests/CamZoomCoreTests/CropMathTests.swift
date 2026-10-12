import XCTest
@testable import CamZoomCore

final class CropMathTests: XCTestCase {

    private let hdSource = CGSize(width: 1920, height: 1080)

    func testDefaultStateReturnsFullFrameForOriginalAspect() {
        let state = CropState(zoom: 1.0, centerX: 0.5, centerY: 0.5, aspect: .original)
        let rect = CropMath.cropRect(source: hdSource, state: state)

        XCTAssertEqual(rect.width, hdSource.width, accuracy: 0.5)
        XCTAssertEqual(rect.height, hdSource.height, accuracy: 0.5)
    }

    func testZoomShrinksCroppedArea() {
        let state = CropState(zoom: 2.0, centerX: 0.5, centerY: 0.5, aspect: .original)
        let rect = CropMath.cropRect(source: hdSource, state: state)

        XCTAssertEqual(rect.width, hdSource.width / 2, accuracy: 0.5)
        XCTAssertEqual(rect.height, hdSource.height / 2, accuracy: 0.5)
    }

    func testCropRectNeverExceedsSourceBounds() {
        // 극단적인 위치(모서리)를 지정해도 잘려나가는 영역이 원본을 벗어나면 안 된다.
        let corners: [(Double, Double)] = [(0, 0), (1, 0), (0, 1), (1, 1)]
        for (x, y) in corners {
            for zoom in [1.0, 1.5, 3.0, 5.0] {
                let state = CropState(zoom: zoom, centerX: x, centerY: y, aspect: .square)
                let rect = CropMath.cropRect(source: hdSource, state: state)

                XCTAssertGreaterThanOrEqual(rect.minX, -0.5)
                XCTAssertGreaterThanOrEqual(rect.minY, -0.5)
                XCTAssertLessThanOrEqual(rect.maxX, hdSource.width + 0.5)
                XCTAssertLessThanOrEqual(rect.maxY, hdSource.height + 0.5)
            }
        }
    }

    func testSquareAspectProducesEqualWidthAndHeight() {
        let state = CropState(zoom: 1.0, centerX: 0.5, centerY: 0.5, aspect: .square)
        let rect = CropMath.cropRect(source: hdSource, state: state)

        XCTAssertEqual(rect.width, rect.height, accuracy: 0.5)
    }

    func testOutputSizeKeepsAspectRatioAndEvenWidth() {
        let rect = CGRect(x: 0, y: 0, width: 1200, height: 900) // 4:3
        let size = CropMath.outputSize(for: rect, targetHeight: 1080)

        XCTAssertEqual(size.height, 1080)
        XCTAssertEqual(size.width / size.height, rect.width / rect.height, accuracy: 0.01)
        XCTAssertEqual(Int(size.width) % 2, 0)
    }

    func testDegenerateSourceReturnsZeroRect() {
        let state = CropState()
        let rect = CropMath.cropRect(source: .zero, state: state)
        XCTAssertEqual(rect, .zero)
    }
}

final class CropMathPlacementTests: XCTestCase {

    func testSquareFitsInsideSixteenNineCentered() {
        let rect = CropMath.placement(
            content: CGSize(width: 1080, height: 1080),
            output: CGSize(width: 1920, height: 1080),
            mode: .fit
        )
        XCTAssertEqual(rect, CGRect(x: 420, y: 0, width: 1080, height: 1080))
    }

    func testSquareFillCoversSixteenNine() {
        let rect = CropMath.placement(
            content: CGSize(width: 1080, height: 1080),
            output: CGSize(width: 1920, height: 1080),
            mode: .fill
        )
        XCTAssertEqual(rect.width, 1920, accuracy: 0.01)
        XCTAssertEqual(rect.height, 1920, accuracy: 0.01)
        XCTAssertEqual(rect.midY, 540, accuracy: 0.01)
    }

    func testSameAspectFillsOutputExactly() {
        let rect = CropMath.placement(
            content: CGSize(width: 1280, height: 720),
            output: CGSize(width: 1920, height: 1080),
            mode: .fit
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func testOrientedSizeSwapsForQuarterTurns() {
        let source = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(CropMath.orientedSize(source: source, rotation: .right), CGSize(width: 1080, height: 1920))
        XCTAssertEqual(CropMath.orientedSize(source: source, rotation: .upsideDown), source)
    }

    func testRotationNextCyclesThroughAllValues() {
        XCTAssertEqual(Rotation.none.next, .right)
        XCTAssertEqual(Rotation.left.next, .none)
    }
}
