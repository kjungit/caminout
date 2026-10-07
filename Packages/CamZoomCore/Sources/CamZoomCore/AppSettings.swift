import Foundation

/// 영상 입력으로 무엇을 쓸지. 검증용 가짜 입력은 측정을 반복 가능하게 하려고 둔다 (검증 계획 4장).
public enum InputSource: Codable, Equatable, Hashable, Sendable {
    /// 실제 카메라. id가 nil이면 기본 카메라.
    case camera(id: String?)
    /// 색 막대 테스트 화면 (색 정확도·FPS 측정용).
    case colorBars
    /// 정지 이미지 파일.
    case image(path: String)
}

/// 화면 모드.
public enum Appearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "시스템"
        case .light:  return "라이트"
        case .dark:   return "다크"
        }
    }
}

/// 출력 관련 설정 (설계서 8.1 OutputSettings).
public struct OutputSettings: Codable, Equatable, Sendable {
    public var input: InputSource
    public var fitMode: OutputFitMode
    /// "효과 끄고 비교"가 꺼진 상태. false면 원본을 그대로 내보낸다.
    public var effectsEnabled: Bool
    /// 검증용 프레임 번호 표시 (A1·B4·B6 누락 측정).
    public var showFrameNumber: Bool

    public init(
        input: InputSource = .camera(id: nil),
        fitMode: OutputFitMode = .fit,
        effectsEnabled: Bool = true,
        showFrameNumber: Bool = false
    ) {
        self.input = input
        self.fitMode = fitMode
        self.effectsEnabled = effectsEnabled
        self.showFrameNumber = showFrameNumber
    }

    private enum CodingKeys: String, CodingKey { case input, fitMode, effectsEnabled, showFrameNumber }

    public init(from decoder: Decoder) throws {
        let d = OutputSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = (try? c.decodeIfPresent(InputSource.self, forKey: .input)) ?? d.input
        fitMode = (try? c.decodeIfPresent(OutputFitMode.self, forKey: .fitMode)) ?? d.fitMode
        effectsEnabled = try c.decodeIfPresent(Bool.self, forKey: .effectsEnabled) ?? d.effectsEnabled
        showFrameNumber = try c.decodeIfPresent(Bool.self, forKey: .showFrameNumber) ?? d.showFrameNumber
    }
}

/// 앱 설정 (설계서 8.1 AppPreferences). 로그인 시 자동 실행은 시스템이 상태를 가지므로 저장하지 않는다.
public struct AppPreferences: Codable, Equatable, Sendable {
    public var appearance: Appearance
    /// Dock 아이콘 없이 메뉴바에만 표시.
    public var menuBarOnly: Bool
    /// 발열·저전력 시 자동 품질 낮춤 (설계서 9.3).
    public var autoQualityReduction: Bool

    public init(appearance: Appearance = .system, menuBarOnly: Bool = false, autoQualityReduction: Bool = true) {
        self.appearance = appearance
        self.menuBarOnly = menuBarOnly
        self.autoQualityReduction = autoQualityReduction
    }

    private enum CodingKeys: String, CodingKey { case appearance, menuBarOnly, autoQualityReduction }

    public init(from decoder: Decoder) throws {
        let d = AppPreferences()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? d.appearance
        menuBarOnly = try c.decodeIfPresent(Bool.self, forKey: .menuBarOnly) ?? d.menuBarOnly
        autoQualityReduction = try c.decodeIfPresent(Bool.self, forKey: .autoQualityReduction) ?? d.autoQualityReduction
    }
}

/// `settings.json` 한 파일에 저장되는 현재 상태 전체 (설계서 8.2).
public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var crop: CropState
    public var output: OutputSettings
    public var preferences: AppPreferences

    public init(
        crop: CropState = CropState(),
        output: OutputSettings = OutputSettings(),
        preferences: AppPreferences = AppPreferences()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.crop = crop
        self.output = output
        self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, crop, output, preferences }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        crop = try c.decodeIfPresent(CropState.self, forKey: .crop) ?? CropState()
        output = try c.decodeIfPresent(OutputSettings.self, forKey: .output) ?? OutputSettings()
        preferences = try c.decodeIfPresent(AppPreferences.self, forKey: .preferences) ?? AppPreferences()
    }
}

/// 이름 붙은 설정 조합. `presets/<id>.json` 하나에 하나씩 저장한다.
public struct Preset: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var crop: CropState

    public init(id: UUID = UUID(), name: String, crop: CropState) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.crop = crop
    }
}
