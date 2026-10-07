import CoreGraphics
import Foundation

/// 사용자가 고를 수 있는 출력 자르기 비율.
/// 기획서 5.1 "자르기 비율" 기능에 대응한다.
public enum AspectOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case original
    case square
    case fourThree
    case sixteenNine

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .original:    return "원본"
        case .square:      return "정사각형"
        case .fourThree:   return "4:3"
        case .sixteenNine: return "16:9"
        }
    }

    /// 원본 소스 크기에 대해 이 비율의 가로/세로 값.
    public func ratio(source: CGSize) -> CGFloat {
        switch self {
        case .original:    return source.width / source.height
        case .square:      return 1
        case .fourThree:   return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        }
    }
}
