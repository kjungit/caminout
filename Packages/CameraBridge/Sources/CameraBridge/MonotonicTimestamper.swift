import CoreMedia

/// sink로 넣는 프레임의 타임스탬프가 항상 증가하도록 보장한다 (G10).
/// 호스트 시간 기준이므로 앱을 다시 실행해도 되돌아가지 않지만, 같은 시각이 두 번 들어오는 경우를 막는다.
public struct MonotonicTimestamper: Sendable {
    /// 같거나 이전 시각이 들어오면 마지막 값에서 이만큼 더한다.
    public static let minimumStep = CMTime(value: 1, timescale: 1_000_000)

    private var last: CMTime = .invalid

    public init() {}

    public mutating func stamp(_ time: CMTime) -> CMTime {
        var result = time.isValid ? time : CMClockGetTime(CMClockGetHostTimeClock())
        if last.isValid, CMTimeCompare(result, last) <= 0 {
            result = CMTimeAdd(last, Self.minimumStep)
        }
        last = result
        return result
    }
}
