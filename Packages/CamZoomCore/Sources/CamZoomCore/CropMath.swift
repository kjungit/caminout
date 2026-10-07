import CoreGraphics

/// CropState를 실제 픽셀 좌표로 바꾸는 순수 계산 로직.
/// 앱(미리보기)과 익스텐션(실제 출력) 양쪽에서 동일하게 써야 하므로
/// AVFoundation이나 UI에 의존하지 않는다.
public enum CropMath {

    /// 원본 영상(source, 좌상단 원점)에서 잘라낼 사각 영역을 계산한다.
    /// 결과는 항상 원본 영역 안에 들어오도록 보정된다.
    public static func cropRect(source: CGSize, state: CropState) -> CGRect {
        guard source.width > 0, source.height > 0 else { return .zero }

        // zoom == 1일 때: 선택한 비율이 원본 안에 들어가는 가장 큰 사각형
        let ratio = state.aspect.ratio(source: source)
        var baseWidth = source.width
        var baseHeight = baseWidth / ratio
        if baseHeight > source.height {
            baseHeight = source.height
            baseWidth = baseHeight * ratio
        }

        // 확대 배율만큼 더 작은 영역만 잘라낸다
        let zoom = max(1.0, state.zoom)
        let width = baseWidth / CGFloat(zoom)
        let height = baseHeight / CGFloat(zoom)

        // 사용자가 지정한 중심점을 기준으로 하되, 원본 밖으로 나가지 않게 보정
        let centerX = clamp(
            CGFloat(state.centerX) * source.width,
            lower: width / 2,
            upper: source.width - width / 2
        )
        let centerY = clamp(
            CGFloat(state.centerY) * source.height,
            lower: height / 2,
            upper: source.height - height / 2
        )

        return CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }

    /// 잘라낸 영역을 내보낼 때 쓸 출력 해상도. 세로 1080 기준으로 비율을 유지한다.
    /// 인코더 호환을 위해 가로 값은 짝수로 맞춘다.
    public static func outputSize(for rect: CGRect, targetHeight: CGFloat = 1080) -> CGSize {
        guard rect.height > 0 else { return CGSize(width: 1920, height: 1080) }
        var width = (targetHeight * rect.width / rect.height).rounded()
        if Int(width) % 2 != 0 { width += 1 }
        return CGSize(width: width, height: targetHeight)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(max(value, lower), upper)
    }
}
