import Foundation

/// 설정 파일 형식 변환 (설계서 8.3). 버전이 낮으면 1→2→3 순서로 변환 함수를 거친다.
public enum SettingsMigration {

    public enum Failure: Error, Equatable {
        case notAnObject
        case missingSchemaVersion
    }

    /// 한 버전을 다음 버전으로 올리는 함수. 키는 "변환 전 버전"이다.
    /// 새 버전을 만들면 여기에 `n: { json in ... }`을 추가하고 `AppSettings.currentSchemaVersion`을 올린다.
    typealias Step = @Sendable ([String: Any]) -> [String: Any]
    static let steps: [Int: Step] = [:]

    /// JSON 바이트를 현재 스키마 버전의 JSON 바이트로 바꾼다.
    /// 현재보다 높은 버전(새 앱에서 만든 파일)은 그대로 둔다. 모르는 필드는 디코딩에서 무시된다.
    public static func migrate(_ data: Data, to target: Int = AppSettings.currentSchemaVersion) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.notAnObject
        }
        guard var version = json["schemaVersion"] as? Int else {
            throw Failure.missingSchemaVersion
        }
        while version < target {
            if let step = steps[version] {
                json = step(json)
            }
            version += 1
            json["schemaVersion"] = version
        }
        return try JSONSerialization.data(withJSONObject: json)
    }
}
