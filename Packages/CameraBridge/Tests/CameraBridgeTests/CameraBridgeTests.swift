import CamZoomShared
import CoreMedia
import CoreVideo
import XCTest
@testable import CameraBridge

final class MonotonicTimestamperTests: XCTestCase {

    func testIncreasingTimesPassThrough() {
        var stamper = MonotonicTimestamper()
        let a = CMTime(value: 100, timescale: 1000)
        let b = CMTime(value: 133, timescale: 1000)
        XCTAssertEqual(stamper.stamp(a), a)
        XCTAssertEqual(stamper.stamp(b), b)
    }

    func testRepeatedOrEarlierTimesAreBumped() {
        var stamper = MonotonicTimestamper()
        let a = CMTime(value: 100, timescale: 1000)
        let first = stamper.stamp(a)
        let second = stamper.stamp(a)
        let third = stamper.stamp(CMTime(value: 50, timescale: 1000))
        XCTAssertEqual(CMTimeCompare(second, first), 1)
        XCTAssertEqual(CMTimeCompare(third, second), 1)
    }

    func testInvalidTimeUsesHostClock() {
        var stamper = MonotonicTimestamper()
        XCTAssertTrue(stamper.stamp(.invalid).isValid)
    }
}

final class SinkSenderTests: XCTestCase {

    func testSendWithoutConnectionReportsNotConnected() throws {
        let sender = SinkSender()
        let buffer = try XCTUnwrap(NoticeImage.makePixelBuffer(format: .hd720))
        XCTAssertEqual(sender.send(buffer, time: .zero), .notConnected)
    }

    func testSampleBufferCarriesTimingAndImage() throws {
        let sender = SinkSender()
        let buffer = try XCTUnwrap(NoticeImage.makePixelBuffer(format: .hd720))
        let time = CMTime(value: 42, timescale: 30)
        let sample = try XCTUnwrap(sender.makeSampleBuffer(buffer, time: time))
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample), time)
        XCTAssertEqual(CMSampleBufferGetDuration(sample), OutputFormat.frameDuration)
        XCTAssertTrue(CMSampleBufferGetImageBuffer(sample) === buffer)
    }
}

final class VirtualCameraStatusTests: XCTestCase {

    func testInUseFollowsCustomPropertyNotRunningSomewhere() {
        var status = VirtualCameraStatus()
        status.installed = true
        status.runningSomewhere = true
        XCTAssertFalse(status.inUse)
        status.sourceActive = true
        XCTAssertTrue(status.inUse)
    }

    func testVersionMismatch() {
        var status = VirtualCameraStatus()
        status.installed = true
        XCTAssertFalse(status.versionMismatch)
        status.protocolVersion = CameraIdentity.protocolVersion + 1
        XCTAssertTrue(status.versionMismatch)
    }

    func testReadingWithoutInstalledCameraDoesNotCrash() {
        // 설치 여부와 상관없이 읽기가 실패 없이 끝나야 한다.
        _ = VirtualCameraMonitor.read()
        _ = VirtualCameraLocator.allDevices()
    }
}
