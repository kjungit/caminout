import AVFoundation
import CoreImage
import CoreGraphics
import Combine
import CamZoomCore

/// 실제 카메라를 열어 프레임을 받고, CamZoomCore.FrameProcessor로 처리한 결과를
/// SwiftUI 화면에 보여주는 앱 전용 컴포넌트.
///
/// 이 클래스는 앱 타깃에만 존재한다. 카메라 익스텐션은 같은 CamZoomCore를 쓰지만
/// AVFoundation 캡처 자체는 앱이 맡고, 처리된 프레임을 sink 스트림으로 넘긴다
/// (기획서 4.1 데이터 흐름, 9.1 타깃 구성 참고).
public final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// 미리보기용으로 줄인 원본 이미지.
    @Published public private(set) var sourcePreview: CGImage?
    /// 상대방에게 보일 처리 결과 이미지.
    @Published public private(set) var outputImage: CGImage?
    /// 현재 카메라의 실제 해상도.
    @Published public private(set) var sourceSize = CGSize(width: 1920, height: 1080)
    /// 사용자에게 보여줄 오류 메시지 (기획서 10장 예외 상황 처리 참고).
    @Published public private(set) var errorMessage: String?

    private let session = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "com.example.camzoom.video")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let stateLock = NSLock()
    private var currentState = CropState.load()
    private var isConfigured = false

    public override init() {
        super.init()
    }

    public func updateState(_ state: CropState) {
        stateLock.lock()
        currentState = state
        stateLock.unlock()
    }

    private var state: CropState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentState
    }

    public func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureAndRun()
                } else {
                    self?.report("카메라 권한이 필요합니다. 시스템 설정 > 개인정보 보호 및 보안 > 카메라에서 허용해 주세요.")
                }
            }
        default:
            report("카메라 권한이 꺼져 있습니다. 시스템 설정 > 개인정보 보호 및 보안 > 카메라에서 허용해 주세요.")
        }
    }

    public func stop() {
        videoQueue.async { [session] in
            session.stopRunning()
        }
    }

    private func configureAndRun() {
        videoQueue.async { [weak self] in
            guard let self else { return }

            if !self.isConfigured {
                guard let device = AVCaptureDevice.default(for: .video) else {
                    self.report("카메라를 찾을 수 없습니다.")
                    return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)

                    self.session.beginConfiguration()
                    self.session.sessionPreset = self.session.canSetSessionPreset(.hd1920x1080)
                        ? .hd1920x1080 : .high
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                    }

                    let output = AVCaptureVideoDataOutput()
                    output.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.videoQueue)
                    if self.session.canAddOutput(output) {
                        self.session.addOutput(output)
                    }

                    self.session.commitConfiguration()
                    self.isConfigured = true
                } catch {
                    self.report("카메라를 열 수 없습니다: \(error.localizedDescription)")
                    return
                }
            }
            self.session.startRunning()
        }
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let sourceExtent = image.extent.size

        // 상대방에게 보일 처리 결과 (CamZoomCore가 앱·익스텐션 공용으로 계산)
        let processed = FrameProcessor.process(image, state: state)
        let outputCG = ciContext.createCGImage(
            processed.image,
            from: CGRect(origin: .zero, size: processed.size)
        )

        // 원본 미리보기는 가볍게 가로 640으로 축소
        let scale = 640 / sourceExtent.width
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let previewCG = ciContext.createCGImage(small, from: small.extent)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.sourceSize != sourceExtent {
                self.sourceSize = sourceExtent
            }
            self.outputImage = outputCG
            self.sourcePreview = previewCG
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = message
        }
    }
}
