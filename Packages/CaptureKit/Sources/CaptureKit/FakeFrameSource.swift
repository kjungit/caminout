@preconcurrency import AVFoundation
import os

/// 녹화 영상·정지 이미지·색 막대를 카메라처럼 30fps로 내보내는 가짜 입력 (검증 계획 4장).
/// 사람이 카메라 앞에서 매번 같은 동작을 하면 측정이 흔들리므로, 반복 가능한 입력을 쓴다.
public final class FakeFrameSource: FrameSource, @unchecked Sendable {

    public enum Content: Sendable {
        case colorBars
        case image(URL)
        /// 끝나면 처음부터 반복 재생한다.
        case video(URL)
    }

    public let content: Content
    public let frameRate: Int
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var stillFrame: CVPixelBuffer?
    private var videoTrack: AVAssetTrack?
    private var reader: AVAssetReader?
    private var readerOutput: AVAssetReaderTrackOutput?
    private var lastVideoFrame: CVPixelBuffer?
    private let logger = Logger(subsystem: "com.kjungit.caminout", category: "fake-capture")

    /// 내보낸 프레임 수.
    public private(set) var deliveredCount: UInt64 = 0

    public init(content: Content, frameRate: Int = 30, queue: DispatchQueue) {
        self.content = content
        self.frameRate = frameRate
        self.queue = queue
    }

    public func start(onFrame: @escaping @Sendable (CapturedFrame) -> Void, onError: @escaping @Sendable (CaptureError) -> Void) {
        queue.async { [self] in
            guard timer == nil else { return }
            switch content {
            case .colorBars:
                stillFrame = TestPattern.colorBars()
            case .image(let url):
                stillFrame = TestPattern.pixelBuffer(contentsOf: url)
                if stillFrame == nil { onError(.cannotReadFile(url.path)); return }
            case .video(let url):
                // 트랙 정보는 비동기로 읽은 뒤 이 큐로 돌아와서 시작한다.
                Task { [self] in
                    let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
                    queue.async { [self] in
                        videoTrack = track
                        guard openReader(url) else { onError(.cannotReadFile(url.path)); return }
                        startTimer(onFrame: onFrame)
                    }
                }
                return
            }
            startTimer(onFrame: onFrame)
        }
    }

    private func startTimer(onFrame: @escaping @Sendable (CapturedFrame) -> Void) {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / frameRate), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, let buffer = self.nextBuffer() else { return }
            self.deliveredCount += 1
            onFrame(CapturedFrame(pixelBuffer: buffer, time: HostClock.now()))
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            reader?.cancelReading()
            reader = nil
        }
    }

    private func nextBuffer() -> CVPixelBuffer? {
        if let stillFrame { return stillFrame }
        guard case .video(let url) = content else { return nil }
        if let sample = readerOutput?.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) {
            lastVideoFrame = buffer
            return buffer
        }
        // 끝까지 읽었으면 처음부터 다시.
        if openReader(url), let sample = readerOutput?.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) {
            lastVideoFrame = buffer
            return buffer
        }
        return lastVideoFrame
    }

    private func openReader(_ url: URL) -> Bool {
        reader?.cancelReading()
        guard let track = videoTrack, let asset = track.asset, let reader = try? AVAssetReader(asset: asset) else {
            logger.error("영상 파일을 열 수 없음: \(url.path, privacy: .public)")
            return false
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return false }
        reader.add(output)
        guard reader.startReading() else { return false }
        self.reader = reader
        self.readerOutput = output
        return true
    }
}
