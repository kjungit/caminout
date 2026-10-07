import Foundation

/// 익스텐션이 장치에 붙여 알려 주는 사용자 정의 속성 (설계서 6장, G3·G5).
/// XPC 없이 CMIO 장치 속성만으로 앱과 익스텐션이 상태를 주고받는다. 값은 모두 문자열이다.
public enum CustomProperty: String, CaseIterable, Sendable {
    /// 화상 앱이 source 스트림을 쓰고 있으면 "1", 아니면 "0".
    case sourceActive = "cact"
    /// 익스텐션의 프로토콜 버전 (`CameraIdentity.protocolVersion`).
    case protocolVersion = "cpvr"
    /// 화상 앱이 고른 출력 형식, 예: "1920x1080".
    case activeFormat = "cafm"
    /// 익스텐션 빌드 번호 (CFBundleVersion). 진단용.
    case extensionBuild = "cbld"

    /// 네 글자 코드.
    public var code: String { rawValue }

    /// CMIOExtensionProperty 이름. "4cc_<코드>_glob_0000" 형식이다.
    public var extensionPropertyName: String { "4cc_\(code)_glob_0000" }

    /// CMIOObjectPropertyAddress의 selector로 쓰는 FourCharCode.
    public var selector: UInt32 {
        code.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
