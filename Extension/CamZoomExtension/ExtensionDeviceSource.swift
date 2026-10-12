import CamZoomShared
import CoreMedia
@preconcurrency import CoreMediaIO
import Foundation
import os

/// 가상 카메라 장치 하나. 스트림 두 개를 연다 (설계서 6장).
/// - sink: 호스트 앱이 처리한 프레임을 넣는 스트림
/// - source: 화상 앱이 읽는 스트림
///
/// 익스텐션은 프레임 전달과 안내 화면 출력만 한다 (설계 원칙 1, ADR-02).
/// 상태는 전부 `queue`에서만 읽고 쓴다.
final class ExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource, @unchecked Sendable {

    /// 이 시간 동안 sink에서 프레임이 오지 않으면 앱이 꺼진 것으로 보고 안내 화면을 내보낸다 (A5).
    static let appTimeoutNanoseconds: UInt64 = 1_000_000_000
    /// 밀린 sink 프레임을 한 번에 최대 몇 개까지 건너뛸지.
    static let maxDrain = 8

    private(set) var device: CMIOExtensionDevice!
    private var sourceStream: SourceStreamSource!
    private var sinkStream: SinkStreamSource!

    private let queue = DispatchQueue(label: "com.kjungit.caminout.extension.device", qos: .userInteractive)
    private let logger = Logger(subsystem: CameraIdentity.extensionBundleID, category: "device")

    private var timer: DispatchSourceTimer?
    private var sourceActive = false
    private var sinkClient: CMIOExtensionClient?
    private var consuming = false
    private var lastSinkFrameNanos: UInt64 = 0
    private var activeFormat = OutputFormat.default
    private var noticeBuffers: [OutputFormat: CVPixelBuffer] = [:]
    private var noticeFormatDescriptions: [OutputFormat: CMVideoFormatDescription] = [:]
    /// 앱이 읽어 가는 사용자 정의 속성 값. CMIO가 어느 스레드에서 읽어도 되도록 잠금으로 보호한다.
    private let publishedLock = NSLock()
    private var published: [CustomProperty: String] = [:]

    init(localizedName: String) {
        super.init()
        device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: CameraIdentity.deviceID,
            legacyDeviceID: nil,
            source: self
        )

        let formats = OutputFormat.advertised.compactMap { format -> CMIOExtensionStreamFormat? in
            guard let description = format.makeFormatDescription() else { return nil }
            return CMIOExtensionStreamFormat(
                formatDescription: description,
                maxFrameDuration: OutputFormat.frameDuration,
                minFrameDuration: OutputFormat.frameDuration,
                validFrameDurations: nil
            )
        }

        sourceStream = SourceStreamSource(
            localizedName: "\(localizedName) Video",
            streamID: CameraIdentity.sourceStreamID,
            formats: formats,
            owner: self
        )
        sinkStream = SinkStreamSource(
            localizedName: "\(localizedName) Input",
            streamID: CameraIdentity.sinkStreamID,
            formats: formats,
            owner: self
        )

        do {
            try device.addStream(sourceStream.stream)
            try device.addStream(sinkStream.stream)
        } catch {
            fatalError("스트림을 추가하지 못했습니다: \(error)")
        }
        published = currentCustomValues()
    }

    // MARK: - 장치 속성

    private static func customProperty(_ property: CustomProperty) -> CMIOExtensionProperty {
        CMIOExtensionProperty(rawValue: property.extensionPropertyName)
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        var properties: Set<CMIOExtensionProperty> = [.deviceTransportType, .deviceModel]
        CustomProperty.allCases.forEach { properties.insert(Self.customProperty($0)) }
        return properties
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = 0x7669_7274 // 'virt' (kIOAudioDeviceTransportTypeVirtual)
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = CameraIdentity.model
        }
        let values = publishedLock.withLock { published }
        for (property, value) in values where properties.contains(Self.customProperty(property)) {
            deviceProperties.setPropertyState(
                CMIOExtensionPropertyState(value: value as NSString),
                forProperty: Self.customProperty(property)
            )
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    /// queue 안(또는 init)에서 부른다.
    private func currentCustomValues() -> [CustomProperty: String] {
        [
            .sourceActive: sourceActive ? "1" : "0",
            .protocolVersion: String(CameraIdentity.protocolVersion),
            .activeFormat: activeFormat.description,
            .extensionBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
        ]
    }

    /// queue 안에서 부른다. 앱이 감시하는 사용자 정의 속성이 바뀌었음을 알린다.
    private func notifyCustomPropertiesChanged() {
        let values = currentCustomValues()
        publishedLock.withLock { published = values }
        var changes: [CMIOExtensionProperty: CMIOExtensionPropertyState<AnyObject>] = [:]
        for (property, value) in values {
            changes[Self.customProperty(property)] = CMIOExtensionPropertyState(value: value as NSString)
        }
        device.notifyPropertiesChanged(changes)
    }

    // MARK: - 스트림 상태 (스트림 소스가 부른다)

    func sourceDidStart() {
        queue.async { [self] in
            sourceActive = true
            logger.info("화상 앱이 카메라를 엶 (\(self.activeFormat.description, privacy: .public))")
            notifyCustomPropertiesChanged()
            updateTimer()
        }
    }

    func sourceDidStop() {
        queue.async { [self] in
            sourceActive = false
            logger.info("화상 앱이 카메라를 닫음")
            notifyCustomPropertiesChanged()
            updateTimer()
        }
    }

    func sourceFormatDidChange(_ format: OutputFormat) {
        queue.async { [self] in
            guard format != activeFormat else { return }
            activeFormat = format
            logger.info("출력 형식 변경: \(format.description, privacy: .public)")
            notifyCustomPropertiesChanged()
        }
    }

    func sinkDidStart(client: CMIOExtensionClient) {
        queue.async { [self] in
            sinkClient = client
            lastSinkFrameNanos = Self.nowNanos()
            logger.info("호스트 앱이 sink에 연결됨")
            updateTimer()
        }
    }

    func sinkDidStop() {
        queue.async { [self] in
            sinkClient = nil
            logger.info("호스트 앱이 sink 연결을 끊음")
            updateTimer()
        }
    }

    // MARK: - 프레임 전달

    /// source나 sink 중 하나라도 열려 있으면 30fps 타이머를 돌린다.
    private func updateTimer() {
        let needed = sourceActive || sinkClient != nil
        if needed, timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now(),
                repeating: .nanoseconds(Int(1_000_000_000 / OutputFormat.frameRate)),
                leeway: .milliseconds(1)
            )
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        } else if !needed, let timer {
            timer.cancel()
            self.timer = nil
        }
    }

    private func tick() {
        if let client = sinkClient, !consuming {
            consuming = true
            consume(from: client, drained: 0)
        }
        if sourceActive, Self.nowNanos() &- lastSinkFrameNanos > Self.appTimeoutNanoseconds {
            sendNotice()
        }
    }

    /// sink에서 프레임을 꺼낸다. 밀려 있으면 가장 최근 것만 보낸다 (지연을 쌓지 않기 위해서).
    private func consume(from client: CMIOExtensionClient, drained: Int) {
        sinkStream.stream.consumeSampleBuffer(from: client) { [weak self] sampleBuffer, sequenceNumber, discontinuity, hasMore, error in
            guard let self else { return }
            let box = SampleBox(sampleBuffer)
            self.queue.async {
                let now = Self.nowNanos()
                guard let sampleBuffer = box.value else {
                    self.consuming = false
                    return
                }
                self.lastSinkFrameNanos = now
                self.sinkStream.stream.notifyScheduledOutputChanged(
                    CMIOExtensionScheduledOutput(sequenceNumber: sequenceNumber, hostTimeInNanoseconds: now)
                )
                if hasMore, drained < Self.maxDrain, let client = self.sinkClient {
                    self.consume(from: client, drained: drained + 1)
                    return
                }
                self.consuming = false
                if self.sourceActive {
                    self.forward(sampleBuffer, discontinuity: discontinuity, now: now)
                }
            }
        }
    }

    private func forward(_ sampleBuffer: CMSampleBuffer, discontinuity: CMIOExtensionStream.DiscontinuityFlags, now: UInt64) {
        // 형식이 막 바뀐 직후에는 크기가 다른 프레임이 올 수 있다. 화상 앱 화면이 흔들리지 않게 버린다.
        if let description = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let dims = CMVideoFormatDescriptionGetDimensions(description)
            guard dims.width == activeFormat.width, dims.height == activeFormat.height else { return }
        }
        sourceStream.stream.send(sampleBuffer, discontinuity: discontinuity, hostTimeInNanoseconds: now)
    }

    private func sendNotice() {
        let format = activeFormat
        if noticeBuffers[format] == nil {
            noticeBuffers[format] = NoticeImage.makePixelBuffer(format: format)
        }
        guard let buffer = noticeBuffers[format] else { return }
        if noticeFormatDescriptions[format] == nil {
            var description: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &description)
            noticeFormatDescriptions[format] = description
        }
        guard let description = noticeFormatDescriptions[format] else { return }

        let now = Self.nowNanos()
        var timing = CMSampleTimingInfo(
            duration: OutputFormat.frameDuration,
            presentationTimeStamp: CMTime(value: CMTimeValue(now), timescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescription: description,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        if let sampleBuffer {
            sourceStream.stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: now)
        }
    }

    /// 호스트 시간 기준 나노초.
    static func nowNanos() -> UInt64 {
        let time = CMClockGetTime(CMClockGetHostTimeClock())
        return UInt64(CMTimeConvertScale(time, timescale: 1_000_000_000, method: .default).value)
    }
}

/// 콜백 큐에서 상태 큐로 샘플 버퍼를 넘기기 위한 상자. 버퍼는 읽기만 한다.
private struct SampleBox: @unchecked Sendable {
    let value: CMSampleBuffer?
    init(_ value: CMSampleBuffer?) { self.value = value }
}
