import AppKit
import SwiftUI

/// 화면 색 (종합 문서 4장). 글자 대비를 위해 라이트는 진하게, 다크는 밝게 조정한 코랄 계열.
enum Theme {
    static let accent = Color(nsColor: NSColor(name: "CamZoomAccent") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 1.0, green: 0.541, blue: 0.4, alpha: 1)      // #FF8A66
            : NSColor(srgbRed: 0.788, green: 0.227, blue: 0.086, alpha: 1)  // #C93A16
    })

    /// 확대 영역 상자 색.
    static let cropBox = Color.yellow
}
