import XCTest
@testable import CamZoomCore

final class CropStateTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suiteName = "CamZoomCoreTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    func testSaveThenLoadReturnsSameValues() {
        let defaults = freshDefaults()
        let original = CropState(zoom: 2.5, centerX: 0.3, centerY: 0.7, aspect: .square)

        original.save(defaults: defaults)
        let loaded = CropState.load(defaults: defaults)

        XCTAssertEqual(loaded, original)
    }

    func testLoadWithoutSavedValueReturnsDefault() {
        let defaults = freshDefaults()
        let loaded = CropState.load(defaults: defaults)

        XCTAssertEqual(loaded, CropState())
    }
}
