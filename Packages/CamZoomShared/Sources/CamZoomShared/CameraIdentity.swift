import Foundation

/// 가상 카메라의 식별자와 이름.
///
/// 화상 앱은 고른 카메라를 장치 UID로 기억한다. 그래서 장치·스트림 ID는 첫 출시 후 절대 바꾸지 않는다 (설계서 13장 G8).
/// 표시 이름은 바꿔도 된다. 앱 이름이 정해지면 `productName`만 고친다.
public enum CameraIdentity {
    /// 앱 이름 (가칭). 실제 화상회의 서비스와 혼동되지 않는 정식 이름으로 바꿀 예정이다.
    public static let productName = "CamZoom"

    /// 화상 앱 카메라 목록에 보이는 이름.
    public static let deviceName = "\(productName) Camera"
    public static let manufacturer = "kjungit"
    public static let model = "\(productName) Virtual Camera"

    public static let deviceID = UUID(uuidString: "5A193A45-3CB5-410D-A8FC-53CC6163D4EF")!
    /// 화상 앱이 읽는 스트림.
    public static let sourceStreamID = UUID(uuidString: "63AEDE4B-3886-46C8-930E-F16AFA8EFFF0")!
    /// 호스트 앱이 프레임을 넣는 스트림.
    public static let sinkStreamID = UUID(uuidString: "5F50D625-5A73-4C36-8A3C-9D58D7869BEF")!

    /// CMIO 장치 UID 문자열. 호스트 앱이 장치를 찾을 때, CaptureKit이 입력 목록에서 자기 자신을 뺄 때 쓴다.
    public static var deviceUID: String { deviceID.uuidString }

    public static let appBundleID = "com.kjungit.caminout"
    public static let extensionBundleID = "com.kjungit.caminout.extension"

    /// 앱↔익스텐션 프로토콜 버전. 사용자 정의 속성의 의미나 sink 규칙이 바뀌면 올린다 (G5).
    /// 앱이 기대하는 값과 익스텐션이 알려 주는 값이 다르면 앱이 확장 교체를 요청한다.
    public static let protocolVersion = 1
}
