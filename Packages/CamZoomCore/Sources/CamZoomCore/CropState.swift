import Foundation

/// 90도 단위 회전.
public enum Rotation: Int, Codable, CaseIterable, Identifiable, Sendable {
    case none = 0
    case right = 90
    case upsideDown = 180
    case left = 270

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .none:       return "0°"
        case .right:      return "90°"
        case .upsideDown: return "180°"
        case .left:       return "270°"
        }
    }

    /// 시계 방향으로 90도 더 돌린 값.
    public var next: Rotation {
        Rotation(rawValue: (rawValue + 90) % 360) ?? .none
    }

    /// 가로·세로가 바뀌는 회전인지.
    public var swapsAxes: Bool { self == .right || self == .left }
}

/// 확대·위치·비율·반전·회전 설정.
/// 기획서 5.1의 1단계 기능(위치 지정 확대, 자르기 비율, 좌우 반전·회전)에 대응한다.
///
/// 좌표(centerX, centerY)는 반전·회전을 적용한 뒤의 화면 기준이다.
/// 사용자가 미리보기에서 보는 방향 그대로 위치를 고르기 때문이다.
public struct CropState: Codable, Equatable, Sendable {
    public static let zoomRange: ClosedRange<Double> = 1.0...5.0

    /// 1.0 = 원본 그대로, 값이 클수록 더 확대된다.
    public var zoom: Double
    /// 확대 기준 위치의 가로 비율. 0은 왼쪽 끝, 1은 오른쪽 끝.
    public var centerX: Double
    /// 확대 기준 위치의 세로 비율. 0은 위쪽 끝, 1은 아래쪽 끝.
    public var centerY: Double
    /// 출력 자르기 비율.
    public var aspect: AspectOption
    /// 좌우 반전.
    public var mirrored: Bool
    /// 90도 단위 회전.
    public var rotation: Rotation

    public init(
        zoom: Double = 1.0,
        centerX: Double = 0.5,
        centerY: Double = 0.5,
        aspect: AspectOption = .original,
        mirrored: Bool = false,
        rotation: Rotation = .none
    ) {
        self.zoom = zoom
        self.centerX = centerX
        self.centerY = centerY
        self.aspect = aspect
        self.mirrored = mirrored
        self.rotation = rotation
    }

    private enum CodingKeys: String, CodingKey {
        case zoom, centerX, centerY, aspect, mirrored, rotation
    }

    /// 없는 필드는 기본값으로 채운다 (설계서 8.3). 이전 버전 파일이 깨지지 않게 하기 위해서다.
    public init(from decoder: Decoder) throws {
        let defaults = CropState()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zoom = try c.decodeIfPresent(Double.self, forKey: .zoom) ?? defaults.zoom
        centerX = try c.decodeIfPresent(Double.self, forKey: .centerX) ?? defaults.centerX
        centerY = try c.decodeIfPresent(Double.self, forKey: .centerY) ?? defaults.centerY
        aspect = (try? c.decodeIfPresent(AspectOption.self, forKey: .aspect)) ?? defaults.aspect
        mirrored = try c.decodeIfPresent(Bool.self, forKey: .mirrored) ?? defaults.mirrored
        rotation = (try? c.decodeIfPresent(Rotation.self, forKey: .rotation)) ?? defaults.rotation
    }

    /// 범위를 벗어난 값을 허용 범위로 보정한 사본.
    public var sanitized: CropState {
        var copy = self
        copy.zoom = zoom.isFinite ? min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound) : 1
        copy.centerX = centerX.isFinite ? min(max(centerX, 0), 1) : 0.5
        copy.centerY = centerY.isFinite ? min(max(centerY, 0), 1) : 0.5
        return copy
    }
}
