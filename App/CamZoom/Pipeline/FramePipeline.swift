import CameraBridge
import CamZoomCore
import CamZoomShared
import CaptureKit
import CoreImage
import CoreMedia
import EffectsKit
import Foundation
import os

/// 1초 동안의 파이프라인 측정값 (설계서 9.4, 검증 계획 B1·B2).
struct PipelineStats: Equatable, Sendable {
    var outputFPS: Double = 0
    var renderP50: Double = 0
    var renderP95: Double = 0
    /// 캡처 → sink 넣기까지 (앱 내부 지연, B1 보조).
    var latencyP50: Double = 0
    /// 합성 중이라 버린 캡처 프레임 누적.
    var droppedBusy: UInt64 = 0
    /// sink 큐가 가득 차 버린 프레임 누적.
    var droppedSink: UInt64 = 0
    var sentToSink: UInt64 = 0
    var poolExhausted: Int = 0
    var sinkConnected = false
}

/// 미리보기에 쓰는 출력 버퍼. 화상 앱으로 나가는 것과 같은 버퍼다 (설계 원칙 2).
struct OutputFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
}

/// 미리보기용 원본 축소 이미지.
struct SourceThumbnail: @unchecked Sendable {
    let image: CGImage
    /// 반전·회전 전 원본 크기.
    let sourceSize: CGSize
}

/// 캡처 → 합성 → 출력 파이프라인 (설계서 5장).
///
/// 큐 세 개: 캡처(captureQueue), 합성·출력(renderQueue), 얼굴 추적(3단계에서 추가).
/// 큐 사이에는 Sendable 값만 넘긴다. 설정은 잠금으로 감싼 스냅샷 하나를 프레임 시작 시 한 번만 읽는다.
final class FramePipeline: @unchecked Sendable {

    let captureQueue = DispatchQueue(label: "com.kjungit.caminout.capture", qos: .userInteractive)
    let renderQueue = DispatchQueue(label: "com.kjungit.caminout.render", qos: .userInteractive)

    private let compositor = Compositor()
    private let sink = SinkSender()
    private let config = OSAllocatedUnfairLock(initialState: PipelineConfig())
    private let inFlight = OSAllocatedUnfairLock(initialState: false)
    private let sinkWanted = OSAllocatedUnfairLock(initialState: false)
    private let logger = Logger(subsystem: "com.kjungit.caminout", category: "pipeline")
    private let signposter = OSSignposter(subsystem: "com.kjungit.caminout", category: .pointsOfInterest)

    // MainActor에서만 바꾼다.
    private var source: FrameSource?
    private var sourceInput: InputSource?

    // renderQueue에서만 바꾼다.
    private var frameIndex: UInt64 = 0
    private var renderDurations: [Double] = []
    private var latencies: [Double] = []
    private var framesThisWindow = 0
    private var windowStart = CFAbsoluteTimeGetCurrent()
    private var droppedBusy: UInt64 = 0

    /// renderQueue에서 불린다.
    var onOutput: (@Sendable (OutputFrame) -> Void)?
    /// renderQueue에서 불린다. 약 10fps.
    var onThumbnail: (@Sendable (SourceThumbnail) -> Void)?
    /// renderQueue에서 불린다. 1초마다.
    var onStats: (@Sendable (PipelineStats) -> Void)?
    /// 캡처 오류. captureQueue에서 불린다.
    var onError: (@Sendable (CaptureError) -> Void)?

    func update(_ newConfig: PipelineConfig) {
        config.withLock { $0 = newConfig }
    }

    var isRunning: Bool { source != nil }

    /// 입력을 시작한다. 같은 입력이 이미 돌고 있으면 그대로 둔다.
    @MainActor
    func start(input: InputSource) {
        if sourceInput == input, source != nil { return }
        stop()
        let newSource: FrameSource
        switch input {
        case .camera(let id):
            newSource = CameraFrameSource(
                deviceID: id,
                excludingIDs: [CameraIdentity.deviceUID],
                excludingNames: [CameraIdentity.deviceName],
                queue: captureQueue
            )
        case .colorBars:
            newSource = FakeFrameSource(content: .colorBars, queue: captureQueue)
        case .image(let path):
            let url = URL(fileURLWithPath: path)
            let isVideo = ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
            newSource = FakeFrameSource(content: isVideo ? .video(url) : .image(url), queue: captureQueue)
        }
        source = newSource
        sourceInput = input
        logger.info("입력 시작: \(String(describing: input), privacy: .public)")
        newSource.start(
            onFrame: { [weak self] frame in self?.didCapture(frame) },
            onError: { [weak self] error in self?.onError?(error) }
        )
    }

    @MainActor
    func stop() {
        source?.stop()
        source = nil
        sourceInput = nil
    }

    /// 가상 카메라 sink 연결을 켜고 끈다. 연결 시도는 renderQueue에서 한다.
    func setSinkEnabled(_ enabled: Bool) {
        sinkWanted.withLock { $0 = enabled }
        renderQueue.async { [self] in
            if enabled {
                if !sink.isConnected, sink.connect() {
                    logger.info("가상 카메라 sink 연결")
                }
            } else if sink.isConnected {
                sink.disconnect()
                logger.info("가상 카메라 sink 해제")
            }
        }
    }

    // MARK: - 프레임 경로

    /// captureQueue. 합성 중인 프레임이 있으면 새 프레임은 버린다 (동시에 처리하는 프레임은 1개).
    private func didCapture(_ frame: CapturedFrame) {
        let accepted = inFlight.withLock { busy -> Bool in
            if busy { return false }
            busy = true
            return true
        }
        guard accepted else {
            renderQueue.async { [self] in droppedBusy += 1 }
            return
        }
        renderQueue.async { [self] in
            defer { inFlight.withLock { $0 = false } }
            process(frame)
        }
    }

    /// renderQueue.
    private func process(_ frame: CapturedFrame) {
        let snapshot = config.withLock { $0 }
        frameIndex &+= 1

        let state = signposter.beginInterval("render")
        let start = CFAbsoluteTimeGetCurrent()
        let output = compositor.render(frame.pixelBuffer, config: snapshot, time: frame.time, frameIndex: frameIndex)
        let renderMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        signposter.endInterval("render", state)

        guard let output else { return }

        if sinkWanted.withLock({ $0 }) {
            if !sink.isConnected { _ = sink.connect() }
            let result = sink.send(output, time: frame.time)
            if result == .sent {
                let now = CMClockGetTime(CMClockGetHostTimeClock())
                latencies.append(CMTimeSubtract(now, frame.time).seconds * 1000)
            } else if case .failed(let status) = result {
                logger.error("sink 넣기 실패 \(status), 다시 연결")
                sink.disconnect()
            }
        }

        onOutput?(OutputFrame(pixelBuffer: output))
        if frameIndex % 3 == 0, let thumbnail = compositor.thumbnail(of: frame.pixelBuffer, crop: snapshot.crop, maxWidth: 480) {
            onThumbnail?(SourceThumbnail(
                image: thumbnail,
                sourceSize: CGSize(width: CVPixelBufferGetWidth(frame.pixelBuffer), height: CVPixelBufferGetHeight(frame.pixelBuffer))
            ))
        }
        record(renderMs: renderMs)
    }

    /// renderQueue.
    private func record(renderMs: Double) {
        renderDurations.append(renderMs)
        framesThisWindow += 1
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - windowStart
        guard elapsed >= 1 else { return }

        var stats = PipelineStats()
        stats.outputFPS = Double(framesThisWindow) / elapsed
        stats.renderP50 = Self.percentile(renderDurations, 0.5)
        stats.renderP95 = Self.percentile(renderDurations, 0.95)
        stats.latencyP50 = Self.percentile(latencies, 0.5)
        stats.droppedBusy = droppedBusy
        stats.droppedSink = sink.droppedCount
        stats.sentToSink = sink.sentCount
        stats.poolExhausted = compositor.poolExhaustedCount
        stats.sinkConnected = sink.isConnected
        onStats?(stats)

        renderDurations.removeAll(keepingCapacity: true)
        latencies.removeAll(keepingCapacity: true)
        framesThisWindow = 0
        windowStart = now
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[index]
    }
}
