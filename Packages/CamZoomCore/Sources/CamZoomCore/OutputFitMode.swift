import Foundation

/// 자른 화면이 화상 앱이 고른 출력 형식과 비율이 다를 때 맞추는 방식 (설계서 7.1의 9번 레이어).
public enum OutputFitMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 전부 보이게 가운데 배치하고 남는 곳은 채운다. 기본값 (ADR-10).
    case fit
    /// 출력을 꽉 채우고 넘치는 부분은 자른다.
    case fill

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fit:  return "전부 보이기"
        case .fill: return "꽉 채우기"
        }
    }
}
