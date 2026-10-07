import CoreGraphics

/// 프레임 파이프라인이 읽는 불변 스냅샷 (설계서 8장).
/// 화면에서 값이 바뀌면 새 스냅샷을 만들어 통째로 교체한다. 프레임 처리 중에는 잠금이 필요 없다.
public struct PipelineConfig: Equatable, Sendable {
    public var crop: CropState
    public var fitMode: OutputFitMode
    public var effectsEnabled: Bool
    public var showFrameNumber: Bool
    /// 화상 앱이 고른 출력 형식의 크기. 아무도 쓰지 않을 때는 미리보기용 기본값.
    public var outputSize: CGSize

    public init(
        crop: CropState = CropState(),
        fitMode: OutputFitMode = .fit,
        effectsEnabled: Bool = true,
        showFrameNumber: Bool = false,
        outputSize: CGSize = CGSize(width: 1920, height: 1080)
    ) {
        self.crop = crop
        self.fitMode = fitMode
        self.effectsEnabled = effectsEnabled
        self.showFrameNumber = showFrameNumber
        self.outputSize = outputSize
    }

    public init(settings: AppSettings, outputSize: CGSize) {
        self.init(
            crop: settings.crop.sanitized,
            fitMode: settings.output.fitMode,
            effectsEnabled: settings.output.effectsEnabled,
            showFrameNumber: settings.output.showFrameNumber,
            outputSize: outputSize
        )
    }
}
