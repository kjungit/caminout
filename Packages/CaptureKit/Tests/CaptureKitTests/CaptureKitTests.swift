import CoreVideo
import XCTest
@testable import CaptureKit

final class TestPatternTests: XCTestCase {

    func testColorBarsHaveEightBarsWithExpectedValues() throws {
        let buffer = try XCTUnwrap(TestPattern.colorBars(width: 800, height: 100))
        XCTAssertEqual(CVPixelBufferGetWidth(buffer), 800)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        for (index, bar) in TestPattern.colorBarValues.enumerated() {
            let x = index * 100 + 50
            let p = base + 50 * CVPixelBufferGetBytesPerRow(buffer) + x * 4
            XCTAssertEqual([p[2], p[1], p[0]], [bar.r, bar.g, bar.b], "bar \(index)")
        }
    }

    func testImageFileIsLoadedAsBGRA() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capturekit-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = CIContext()
        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 32))
        try ctx.writePNGRepresentation(of: image, to: url, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)

        let buffer = try XCTUnwrap(TestPattern.pixelBuffer(contentsOf: url))
        XCTAssertEqual(CVPixelBufferGetWidth(buffer), 64)
        XCTAssertEqual(CVPixelBufferGetHeight(buffer), 32)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(buffer), kCVPixelFormatType_32BGRA)
    }
}

final class FakeFrameSourceTests: XCTestCase {

    func testColorBarsSourceDeliversFramesWithIncreasingTime() {
        let source = FakeFrameSource(content: .colorBars, frameRate: 30, queue: DispatchQueue(label: "test.capture"))
        let gotFrames = expectation(description: "frames")
        let times = Times()
        source.start(onFrame: { frame in
            if times.append(frame.time.seconds) == 5 { gotFrames.fulfill() }
        }, onError: { error in XCTFail("\(error)") })
        wait(for: [gotFrames], timeout: 2)
        source.stop()

        let values = times.values
        XCTAssertEqual(values, values.sorted())
    }

    func testMissingImageReportsError() {
        let source = FakeFrameSource(content: .image(URL(fileURLWithPath: "/nonexistent.png")), queue: DispatchQueue(label: "test.capture"))
        let failed = expectation(description: "error")
        source.start(onFrame: { _ in }, onError: { error in
            if case .cannotReadFile = error { failed.fulfill() }
        })
        wait(for: [failed], timeout: 2)
    }
}

private final class Times: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    func append(_ value: Double) -> Int {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
        return storage.count
    }

    var values: [Double] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
