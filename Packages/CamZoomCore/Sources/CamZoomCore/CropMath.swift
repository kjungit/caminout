import CoreGraphics

/// CropState를 실제 픽셀 좌표로 바꾸는 순수 계산 로직.
/// UI(확대 영역 표시)와 EffectsKit(실제 출력)이 같은 계산을 쓰도록
/// AVFoundation이나 UI에 의존하지 않는다.
public enum CropMath {

    /// 반전·회전을 적용한 뒤의 원본 크기. 자르기 좌표는 이 크기 기준이다.
    public static func orientedSize(source: CGSize, rotation: Rotation) -> CGSize {
        rotation.swapsAxes ? CGSize(width: source.height, height: source.width) : source
    }

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

    /// 자른 화면(content)을 출력 형식(output) 안에 놓을 위치. 좌하단 원점이 아닌 일반 사각형 좌표.
    /// - fit: 비율을 유지한 채 전부 보이게 하고 남는 곳은 비운다 (16:9 안 정사각형 가운데 배치).
    /// - fill: 비율을 유지한 채 출력을 꽉 채우고 넘치는 부분은 잘린다.
    public static func placement(content: CGSize, output: CGSize, mode: OutputFitMode) -> CGRect {
        guard content.width > 0, content.height > 0, output.width > 0, output.height > 0 else {
            return CGRect(origin: .zero, size: output)
        }
        let scaleX = output.width / content.width
        let scaleY = output.height / content.height
        let scale = mode == .fit ? min(scaleX, scaleY) : max(scaleX, scaleY)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: (output.width - size.width) / 2,
            y: (output.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(max(value, lower), upper)
    }
}
