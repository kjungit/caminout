import CoreMedia
import CoreVideo
import XCTest
@testable import CamZoomShared

final class CamZoomSharedTests: XCTestCase {

    func testIdentifiersAreDistinct() {
        let ids = [CameraIdentity.deviceID, CameraIdentity.sourceStreamID, CameraIdentity.sinkStreamID]
        XCTAssertEqual(Set(ids).count, 3)
    }

    /// 장치 UID는 첫 출시 후 바뀌면 안 된다 (G8). 실수로 바꾸면 이 테스트가 깨진다.
    func testDeviceUIDIsPinned() {
        XCTAssertEqual(CameraIdentity.deviceUID, "5A193A45-3CB5-410D-A8FC-53CC6163D4EF")
    }

    func testCustomPropertyNamesFollowCMIOFormat() {
        XCTAssertEqual(CustomProperty.sourceActive.extensionPropertyName, "4cc_cact_glob_0000")
        for property in CustomProperty.allCases {
            XCTAssertEqual(property.code.utf8.count, 4)
        }
        XCTAssertEqual(Set(CustomProperty.allCases.map(\.selector)).count, CustomProperty.allCases.count)
    }

    func testSelectorIsBigEndianFourCharCode() {
        // 'cact' = 0x63616374
        XCTAssertEqual(CustomProperty.sourceActive.selector, 0x6361_6374)
    }

    func testOutputFormatStringRoundTrip() {
        for format in OutputFormat.advertised {
            XCTAssertEqual(OutputFormat(string: format.description), format)
        }
        XCTAssertNil(OutputFormat(string: "abc"))
        XCTAssertNil(OutputFormat(string: "0x10"))
    }

    func testDefaultFormatIsSixteenNine() {
        XCTAssertEqual(OutputFormat.advertised.first, .hd1080)
        XCTAssertEqual(OutputFormat.frameRate, 30)
    }

    func testFormatDescriptionHasRequestedDimensions() throws {
        let description = try XCTUnwrap(OutputFormat.square1080.makeFormatDescription())
        let dims = CMVideoFormatDescriptionGetDimensions(description)
        XCTAssertEqual(dims.width, 1080)
        XCTAssertEqual(dims.height, 1080)
    }

    func testNoticeImageMatchesFormatAndIsNotBlank() throws {
        let buffer = try XCTUnwrap(NoticeImage.makePixelBuffer(format: .hd720))
        XCTAssertEqual(CVPixelBufferGetWidth(buffer), 1280)
        XCTAssertEqual(CVPixelBufferGetHeight(buffer), 720)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(buffer), kCVPixelFormatType_32BGRA)
        XCTAssertNotNil(CVPixelBufferGetIOSurface(buffer))

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        // 구석은 어두운 배경, 가운데 위쪽 원은 강조색이어야 한다.
        let corner = base[0 * bytesPerRow + 0 + 2]
        let dotRow = 720 / 2 - Int(720 * 0.08) - Int(720 * 0.06)
        let dot = base[dotRow * bytesPerRow + (1280 / 2) * 4 + 2]
        XCTAssertLessThan(corner, 50)
        XCTAssertGreaterThan(dot, 200)
    }
}
