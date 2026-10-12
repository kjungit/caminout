import Foundation

/// 자동 품질 낮춤 단계 (설계서 9.3). 숫자가 클수록 많이 낮춘다.
///
/// 1단계 MVP에서 실제로 적용되는 것은 3단계의 출력 15fps뿐이다.
/// 추적·사람 분리·캐릭터 값은 해당 기능이 들어오는 단계(2~5단계)에서 읽는다.
public enum QualityLevel: Int, Comparable, CaseIterable, Codable, Sendable {
    case normal = 0
    case reduced = 1
    case low = 2
    case minimal = 3

    public static func < (lhs: QualityLevel, rhs: QualityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 한 단계 더 낮춘 값. 이미 가장 낮으면 그대로.
    public var lowered: QualityLevel { QualityLevel(rawValue: rawValue + 1) ?? self }
    /// 한 단계 되돌린 값. 이미 정상이면 그대로.
    public var raised: QualityLevel { QualityLevel(rawValue: rawValue - 1) ?? self }

    /// 얼굴 추적 주기.
    public var trackingFPS: Int {
        switch self {
        case .normal: return 30
        case .reduced: return 15
        case .low, .minimal: return 10
        }
    }

    /// 출력 최대 프레임 레이트. nil이면 입력 그대로.
    public var outputFPSLimit: Int? {
        self == .minimal ? 15 : nil
    }

    /// 사람 분리를 '빠름' 품질로 돌릴지.
    public var fastSegmentation: Bool { self >= .reduced }
    public var faceWarpEnabled: Bool { self < .low }
    /// 3D 캐릭터를 쓸 수 있는지. 아니면 2D로 대체한다.
    public var character3DEnabled: Bool { self < .low }
    public var backgroundEnabled: Bool { self < .minimal }
    public var characterEnabled: Bool { self < .minimal }
}

/// 품질 단계를 정하는 조건 (설계서 9.3).
public struct QualityConditions: Equatable, Sendable {
    /// `ProcessInfo.ThermalState`와 같은 순서. 패키지가 Foundation 플랫폼 타입에 묶이지 않게 따로 둔다.
    public enum Thermal: Int, Comparable, Sendable {
        case nominal, fair, serious, critical

        public static func < (lhs: Thermal, rhs: Thermal) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var thermal: Thermal
    public var lowPowerMode: Bool
    /// 3초 이상 이어지는 프레임 누락.
    public var sustainedFrameDrops: Bool

    public init(thermal: Thermal = .nominal, lowPowerMode: Bool = false, sustainedFrameDrops: Bool = false) {
        self.thermal = thermal
        self.lowPowerMode = lowPowerMode
        self.sustainedFrameDrops = sustainedFrameDrops
    }

    /// 조건이 요구하는 단계. 여러 조건이 겹치면 가장 낮은 품질을 고른다.
    public var targetLevel: QualityLevel {
        var level = QualityLevel.normal
        if thermal >= .fair || lowPowerMode { level = max(level, .reduced) }
        if thermal >= .serious || sustainedFrameDrops { level = max(level, .low) }
        if thermal >= .critical { level = .minimal }
        return level
    }

    /// 현재 단계의 이유. 메뉴바 알림 문구에 쓴다.
    public var reason: String? {
        if thermal >= .fair { return "맥이 뜨거워져서" }
        if sustainedFrameDrops { return "처리가 밀려서" }
        if lowPowerMode { return "저전력 모드라서" }
        return nil
    }
}

/// 조건에 따라 품질 단계를 한 단계씩 낮추고, 회복 후 30초마다 한 단계씩 되돌린다 (설계서 9.3).
///
/// 시간은 밖에서 넣어 준다. 그래야 테스트에서 30초를 기다리지 않아도 된다.
public struct QualityGovernor: Sendable {
    public static let recoveryDelay: TimeInterval = 30

    public private(set) var level: QualityLevel = .normal
    /// 조건이 지금 단계보다 좋아진 시각. 이때부터 30초가 지나면 한 단계 되돌린다.
    private var recoveringSince: TimeInterval?

    public init() {}

    /// 조건을 반영하고 바뀐 단계를 돌려준다. 1초 안팎 간격으로 부른다.
    /// `enabled`가 false면(설정에서 끔) 바로 정상으로 돌아간다.
    @discardableResult
    public mutating func update(_ conditions: QualityConditions, enabled: Bool, now: TimeInterval) -> QualityLevel {
        guard enabled else {
            level = .normal
            recoveringSince = nil
            return level
        }
        let target = conditions.targetLevel
        if target > level {
            level = level.lowered
            recoveringSince = nil
        } else if target < level {
            if let since = recoveringSince {
                if now - since >= Self.recoveryDelay {
                    level = level.raised
                    recoveringSince = now
                }
            } else {
                recoveringSince = now
            }
        } else {
            recoveringSince = nil
        }
        return level
    }
}

/// 1초 단위 프레임 누락 기록으로 "3초 이상 이어지는 누락"을 판단한다 (설계서 5장).
public struct SustainedDropDetector: Sendable {
    /// 이 비율 이상 버린 1초 구간을 누락 구간으로 본다.
    public static let dropRatioThreshold = 0.1
    public static let requiredSeconds = 3

    private var consecutive = 0

    public init() {}

    public var isSustained: Bool { consecutive >= Self.requiredSeconds }

    /// 1초 구간 하나를 기록한다.
    public mutating func record(dropped: Int, delivered: Int) {
        let total = dropped + delivered
        let ratio = total > 0 ? Double(dropped) / Double(total) : 0
        consecutive = ratio >= Self.dropRatioThreshold ? consecutive + 1 : 0
    }

    public mutating func reset() {
        consecutive = 0
    }
}
