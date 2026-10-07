import Foundation

/// 확대·위치·비율 설정. UserDefaults에 JSON으로 저장해 재실행 후에도 유지한다.
/// 기획서 5.1 "설정 고정·자동 저장" 기능에 대응한다.
public struct CropState: Codable, Equatable, Sendable {
    /// 1.0 = 원본 그대로, 값이 클수록 더 확대된다.
    public var zoom: Double
    /// 확대 기준 위치의 가로 비율. 0은 왼쪽 끝, 1은 오른쪽 끝.
    public var centerX: Double
    /// 확대 기준 위치의 세로 비율. 0은 위쪽 끝, 1은 아래쪽 끝.
    public var centerY: Double
    /// 출력 자르기 비율.
    public var aspect: AspectOption

    public init(
        zoom: Double = 1.0,
        centerX: Double = 0.5,
        centerY: Double = 0.5,
        aspect: AspectOption = .original
    ) {
        self.zoom = zoom
        self.centerX = centerX
        self.centerY = centerY
        self.aspect = aspect
    }

    private static let storageKey = "CamZoom.CropState"

    /// UserDefaults에서 마지막으로 저장한 설정을 불러온다. 없으면 기본값을 반환한다.
    public static func load(defaults: UserDefaults = .standard) -> CropState {
        guard
            let data = defaults.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode(CropState.self, from: data)
        else {
            return CropState()
        }
        return saved
    }

    /// 현재 설정을 UserDefaults에 저장한다.
    public func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
