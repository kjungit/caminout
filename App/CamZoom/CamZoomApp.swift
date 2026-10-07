import SwiftUI
import CamZoomCore

@main
struct CamZoomApp: App {
    var body: some Scene {
        WindowGroup("CamZoom") {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var state = CropState.load()
    @State private var pinchBase: Double?

    private let maxZoom = 5.0

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("카메라 원본").font(.headline)
                    Text("클릭하거나 드래그해서 확대할 위치를 정하세요")
                        .font(.caption).foregroundStyle(.secondary)
                    sourceView
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("상대방에게 보이는 화면").font(.headline)
                    Text("트랙패드 핀치로도 확대·축소할 수 있어요")
                        .font(.caption).foregroundStyle(.secondary)
                    outputView
                }
            }
            controls
            if let error = camera.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 560)
        .onAppear {
            camera.updateState(state)
            camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: state) { newValue in
            camera.updateState(newValue)
            newValue.save() // 기획서 5.1 "설정 고정·자동 저장"
        }
    }

    // 원본 화면 + 잘라낼 영역 표시
    private var sourceView: some View {
        ZStack {
            Rectangle().fill(Color.black)
            if let img = camera.sourcePreview {
                Image(decorative: img, scale: 1).resizable()
            }
        }
        .aspectRatio(camera.sourceSize, contentMode: .fit)
        .overlay(cropOverlay)
        .frame(maxWidth: .infinity)
    }

    private var cropOverlay: some View {
        GeometryReader { geo in
            let source = camera.sourceSize
            let rect = CropMath.cropRect(source: source, state: state)
            let scaleX = geo.size.width / source.width
            let scaleY = geo.size.height / source.height
            let box = CGRect(
                x: rect.minX * scaleX,
                y: rect.minY * scaleY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            )

            ZStack(alignment: .topLeading) {
                // 잘려나가는 부분은 어둡게
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    path.addRect(box)
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

                // 보여질 영역 테두리
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in moveCenter(to: value.location, in: geo.size) }
            )
        }
    }

    // 결과 화면
    private var outputView: some View {
        let rect = CropMath.cropRect(source: camera.sourceSize, state: state)
        let ratio = rect.height > 0 ? rect.width / rect.height : 16.0 / 9.0
        return ZStack {
            Rectangle().fill(Color.black)
            if let img = camera.outputImage {
                Image(decorative: img, scale: 1).resizable()
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    if pinchBase == nil { pinchBase = state.zoom }
                    state.zoom = min(max((pinchBase ?? 1) * Double(value), 1), maxZoom)
                }
                .onEnded { _ in pinchBase = nil }
        )
    }

    // 조작 버튼
    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("확대").frame(width: 40, alignment: .leading)
                Slider(value: $state.zoom, in: 1...maxZoom)
                Text(String(format: "%.1f배", state.zoom))
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
            HStack {
                Text("비율").frame(width: 40, alignment: .leading)
                Picker("", selection: $state.aspect) {
                    ForEach(AspectOption.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button("가운데로") {
                    state.centerX = 0.5
                    state.centerY = 0.5
                }
                Button("초기화") { state = CropState() }
            }
        }
    }

    // 클릭·드래그한 위치를 확대 기준점으로 저장
    private func moveCenter(to point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        var newState = state
        newState.centerX = Double(min(max(point.x / size.width, 0), 1))
        newState.centerY = Double(min(max(point.y / size.height, 0), 1))

        // 원본 밖으로 나가지 않는 위치로 다시 보정해서 저장
        let source = camera.sourceSize
        let rect = CropMath.cropRect(source: source, state: newState)
        newState.centerX = Double(rect.midX / source.width)
        newState.centerY = Double(rect.midY / source.height)
        state = newState
    }
}
