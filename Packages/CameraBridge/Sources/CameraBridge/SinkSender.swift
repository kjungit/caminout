import CamZoomShared
import CoreMedia
import CoreMediaIO
import CoreVideo
import os

/// 처리한 프레임을 가상 카메라의 sink 스트림 큐에 넣는다 (설계서 6장, ADR-03).
/// 애플 개발자 포럼에서 안내된 `CMIOStreamCopyBufferQueue` + `CMSimpleQueueEnqueue` 경로다.
///
/// renderQueue 하나에서만 호출한다.
public final class SinkSender: @unchecked Sendable {

    public enum SendResult: Equatable, Sendable {
        case sent
        /// 큐가 가득 차 이 프레임을 버렸다. 다음 프레임을 보낸다.
        case dropped
        case notConnected
        case failed(OSStatus)
    }

    private var device: VirtualCameraDevice?
    private var queue: CMSimpleQueue?
    private var timestamper = MonotonicTimestamper()
    private var formatDescription: CMVideoFormatDescription?
    private let logger = Logger(subsystem: "com.kjungit.caminout", category: "sink")

    public private(set) var sentCount: UInt64 = 0
    public private(set) var droppedCount: UInt64 = 0

    public init() {}

    public var isConnected: Bool { queue != nil }

    /// 장치를 찾아 sink 스트림을 연다. 이미 열려 있으면 그대로 둔다.
    @discardableResult
    public func connect() -> Bool {
        if queue != nil { return true }
        guard let found = VirtualCameraLocator.find() else { return false }

        var unmanagedQueue: Unmanaged<CMSimpleQueue>?
        let status = CMIOStreamCopyBufferQueue(found.sinkStreamID, { _, _, _ in }, nil, &unmanagedQueue)
        guard status == noErr, let unmanagedQueue else {
            logger.error("sink 큐 열기 실패: \(status)")
            return false
        }
        let startStatus = CMIODeviceStartStream(found.deviceID, found.sinkStreamID)
        guard startStatus == noErr else {
            logger.error("sink 스트림 시작 실패: \(startStatus)")
            unmanagedQueue.release()
            return false
        }
        queue = unmanagedQueue.takeRetainedValue()
        device = found
        logger.info("sink 연결됨: device \(found.deviceID) stream \(found.sinkStreamID)")
        return true
    }

    public func disconnect() {
        if let device {
            CMIODeviceStopStream(device.deviceID, device.sinkStreamID)
        }
        device = nil
        queue = nil
        formatDescription = nil
    }

    /// 프레임 하나를 sink 큐에 넣는다.
    public func send(_ pixelBuffer: CVPixelBuffer, time: CMTime) -> SendResult {
        guard let queue else { return .notConnected }
        if CMSimpleQueueGetCount(queue) >= CMSimpleQueueGetCapacity(queue) {
            droppedCount += 1
            return .dropped
        }
        guard let sampleBuffer = makeSampleBuffer(pixelBuffer, time: timestamper.stamp(time)) else {
            return .failed(-1)
        }
        let status = CMSimpleQueueEnqueue(queue, element: Unmanaged.passRetained(sampleBuffer).toOpaque())
        if status != noErr {
            // 넣지 못했으면 위에서 올린 참조를 돌려준다.
            Unmanaged.passUnretained(sampleBuffer).release()
            droppedCount += 1
            return status == kCMSimpleQueueError_QueueIsFull ? .dropped : .failed(status)
        }
        sentCount += 1
        return .sent
    }

    func makeSampleBuffer(_ pixelBuffer: CVPixelBuffer, time: CMTime) -> CMSampleBuffer? {
        if formatDescription == nil || !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: pixelBuffer) {
            var description: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &description)
            formatDescription = description
        }
        guard let formatDescription else { return nil }
        var timing = CMSampleTimingInfo(
            duration: OutputFormat.frameDuration,
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}
