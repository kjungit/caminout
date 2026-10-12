import AppKit
import CoreVideo
import QuartzCore

/// 출력 버퍼를 미리보기 화면에 바로 붙인다.
/// 매 프레임 SwiftUI를 다시 그리지 않도록 관찰 상태를 거치지 않고 레이어에 IOSurface를 직접 넣는다.
@MainActor
final class PreviewHub {
    private let views = NSHashTable<PixelBufferLayerView>.weakObjects()
    private(set) var latest: OutputFrame?

    func register(_ view: PixelBufferLayerView) {
        views.add(view)
        if let latest { view.display(latest.pixelBuffer) }
    }

    func publish(_ frame: OutputFrame) {
        latest = frame
        for view in views.allObjects {
            view.display(frame.pixelBuffer)
        }
    }

    func clear() {
        latest = nil
        for view in views.allObjects {
            view.clear()
        }
    }
}

/// IOSurface 기반 픽셀 버퍼를 복사 없이 보여주는 뷰.
final class PixelBufferLayerView: NSView {
    /// 표시 중인 버퍼. 붙잡아 둬야 풀이 표시 중인 버퍼를 다시 쓰지 않는다.
    private var current: CVPixelBuffer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func display(_ buffer: CVPixelBuffer) {
        current = buffer
        if let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() {
            layer?.contents = surface
        }
    }

    func clear() {
        current = nil
        layer?.contents = nil
    }
}
