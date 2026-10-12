import CamZoomCore
import SwiftUI

/// 화상 앱으로 나가는 것과 같은 출력 버퍼를 보여준다.
struct OutputPreview: NSViewRepresentable {
    let hub: PreviewHub

    func makeNSView(context: Context) -> PixelBufferLayerView {
        let view = PixelBufferLayerView(frame: .zero)
        hub.register(view)
        return view
    }

    func updateNSView(_ nsView: PixelBufferLayerView, context: Context) {}
}

/// "상대방에게 보이는 화면". 보이는 동안 카메라를 켠다.
struct OutputPreviewPanel: View {
    @Environment(AppState.self) private var app
    var cornerRadius: CGFloat = 10
    var showsStats = false

    var body: some View {
        ZStack {
            OutputPreview(hub: app.previewHub)
            if !app.isCapturing {
                placeholder
            }
            if showsStats {
                DebugOverlay(stats: app.stats)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(8)
            }
        }
        .aspectRatio(app.outputAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onAppear { app.previewAppeared() }
        .onDisappear { app.previewDisappeared() }
    }

    @ViewBuilder private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash")
                .font(.title)
            if !app.cameraAuthorized, case .camera = app.settings.output.input {
                Text("카메라 권한이 필요해요")
                Button("권한 허용") { Task { await app.requestCameraAccess() } }
            } else {
                Text("카메라 꺼짐")
            }
        }
        .foregroundStyle(.white.opacity(0.8))
    }
}

/// 원본 축소 화면 위에 확대 영역(노란 상자)을 그리고, 클릭·드래그로 위치를 옮긴다.
struct CropSelector: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let oriented = app.orientedSourceSize
        ZStack {
            Rectangle().fill(.black)
            if let thumbnail = app.sourceThumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .interpolation(.medium)
            }
        }
        .aspectRatio(oriented, contentMode: .fit)
        .overlay(overlay(oriented: oriented))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("확대 위치 선택")
    }

    private func overlay(oriented: CGSize) -> some View {
        GeometryReader { geo in
            let rect = CropMath.cropRect(source: oriented, state: app.settings.crop)
            let sx = geo.size.width / max(oriented.width, 1)
            let sy = geo.size.height / max(oriented.height, 1)
            let box = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy)

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    path.addRect(box)
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

                Rectangle()
                    .stroke(Theme.cropBox, lineWidth: 2)
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in moveCenter(to: value.location, in: geo.size, oriented: oriented) }
            )
        }
    }

    /// 클릭·드래그한 위치를 확대 기준점으로 저장한다. 원본 밖으로 나가지 않는 위치로 보정한다.
    private func moveCenter(to point: CGPoint, in size: CGSize, oriented: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        var crop = app.settings.crop
        crop.centerX = Double(min(max(point.x / size.width, 0), 1))
        crop.centerY = Double(min(max(point.y / size.height, 0), 1))
        let rect = CropMath.cropRect(source: oriented, state: crop)
        crop.centerX = Double(rect.midX / oriented.width)
        crop.centerY = Double(rect.midY / oriented.height)
        app.settings.crop = crop
    }
}

/// 개발 빌드 미리보기 구석의 측정값 (설계서 9.4).
struct DebugOverlay: View {
    let stats: PipelineStats

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.1f fps · 합성 p50 %.1f / p95 %.1f ms", stats.outputFPS, stats.renderP50, stats.renderP95))
            Text(String(format: "앱 내부 지연 %.0f ms · sink %@", stats.latencyP50, stats.sinkConnected ? "연결" : "끊김"))
            Text("버림: 합성 \(stats.droppedBusy) · sink \(stats.droppedSink) · 풀 고갈 \(stats.poolExhausted)")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}
