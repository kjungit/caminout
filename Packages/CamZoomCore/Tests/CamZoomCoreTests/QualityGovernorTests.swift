import XCTest
@testable import CamZoomCore

final class QualityGovernorTests: XCTestCase {

    func testTargetLevelFollowsDesignTable() {
        XCTAssertEqual(QualityConditions().targetLevel, .normal)
        XCTAssertEqual(QualityConditions(thermal: .fair).targetLevel, .reduced)
        XCTAssertEqual(QualityConditions(lowPowerMode: true).targetLevel, .reduced)
        XCTAssertEqual(QualityConditions(thermal: .serious).targetLevel, .low)
        XCTAssertEqual(QualityConditions(sustainedFrameDrops: true).targetLevel, .low)
        XCTAssertEqual(QualityConditions(thermal: .critical).targetLevel, .minimal)
        // 여러 조건이 겹치면 가장 낮은 품질.
        XCTAssertEqual(QualityConditions(thermal: .fair, sustainedFrameDrops: true).targetLevel, .low)
    }

    func testLowersOneStepPerUpdate() {
        var governor = QualityGovernor()
        let critical = QualityConditions(thermal: .critical)

        XCTAssertEqual(governor.update(critical, enabled: true, now: 0), .reduced)
        XCTAssertEqual(governor.update(critical, enabled: true, now: 1), .low)
        XCTAssertEqual(governor.update(critical, enabled: true, now: 2), .minimal)
        XCTAssertEqual(governor.update(critical, enabled: true, now: 3), .minimal)
    }

    func testRaisesOneStepEvery30SecondsAfterRecovery() {
        var governor = QualityGovernor()
        let serious = QualityConditions(thermal: .serious)
        governor.update(serious, enabled: true, now: 0)
        governor.update(serious, enabled: true, now: 1)
        XCTAssertEqual(governor.level, .low)

        let normal = QualityConditions()
        XCTAssertEqual(governor.update(normal, enabled: true, now: 10), .low)
        XCTAssertEqual(governor.update(normal, enabled: true, now: 39), .low)
        XCTAssertEqual(governor.update(normal, enabled: true, now: 40), .reduced)
        XCTAssertEqual(governor.update(normal, enabled: true, now: 69), .reduced)
        XCTAssertEqual(governor.update(normal, enabled: true, now: 70), .normal)
    }

    func testRecoveryTimerRestartsWhenConditionReturns() {
        var governor = QualityGovernor()
        governor.update(QualityConditions(lowPowerMode: true), enabled: true, now: 0)
        XCTAssertEqual(governor.level, .reduced)

        governor.update(QualityConditions(), enabled: true, now: 10)
        // 회복 대기 중에 다시 저전력 모드가 되면 대기가 처음부터 시작된다.
        governor.update(QualityConditions(lowPowerMode: true), enabled: true, now: 20)
        governor.update(QualityConditions(), enabled: true, now: 30)
        XCTAssertEqual(governor.update(QualityConditions(), enabled: true, now: 45), .reduced)
        XCTAssertEqual(governor.update(QualityConditions(), enabled: true, now: 60), .normal)
    }

    func testDisabledReturnsToNormalImmediately() {
        var governor = QualityGovernor()
        governor.update(QualityConditions(thermal: .fair), enabled: true, now: 0)
        XCTAssertEqual(governor.level, .reduced)
        XCTAssertEqual(governor.update(QualityConditions(thermal: .critical), enabled: false, now: 1), .normal)
    }

    func testOnlyMinimalLimitsOutputFrameRate() {
        XCTAssertNil(QualityLevel.normal.outputFPSLimit)
        XCTAssertNil(QualityLevel.low.outputFPSLimit)
        XCTAssertEqual(QualityLevel.minimal.outputFPSLimit, 15)
    }

    func testSustainedDropsNeedThreeConsecutiveSeconds() {
        var detector = SustainedDropDetector()
        detector.record(dropped: 5, delivered: 25)
        detector.record(dropped: 5, delivered: 25)
        XCTAssertFalse(detector.isSustained)
        detector.record(dropped: 5, delivered: 25)
        XCTAssertTrue(detector.isSustained)

        // 한 구간이라도 정상이면 처음부터 다시 센다.
        detector.record(dropped: 1, delivered: 29)
        XCTAssertFalse(detector.isSustained)
    }

    func testIdleSecondsDoNotCountAsDrops() {
        var detector = SustainedDropDetector()
        for _ in 0..<5 { detector.record(dropped: 0, delivered: 0) }
        XCTAssertFalse(detector.isSustained)
    }
}
