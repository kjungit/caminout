import CamZoomShared
import SwiftUI

/// 메인 창: 왼쪽 탭, 가운데 "상대방에게 보이는 화면", 오른쪽 설정 패널 (종합 문서 4장).
struct MainWindowView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case adjust, decorate, effects, character
        var id: String { rawValue }

        var title: String {
            switch self {
            case .adjust: return "조절"
            case .decorate: return "꾸미기"
            case .effects: return "효과"
            case .character: return "캐릭터"
            }
        }

        var icon: String {
            switch self {
            case .adjust: return "crop"
            case .decorate: return "paintpalette"
            case .effects: return "sparkles"
            case .character: return "face.smiling"
            }
        }

        /// 기능이 들어오는 단계 (기획서 5.2).
        var stage: Int {
            switch self {
            case .adjust: return 1
            case .decorate: return 2
            case .effects: return 3
            case .character: return 4
            }
        }
    }

    @Environment(AppState.self) private var app
    @State private var tab: Tab = .adjust
    @AppStorage("showDebugOverlay") private var showDebugOverlay = false

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("상대방에게 보이는 화면").font(.title3.weight(.semibold))
                    Spacer()
                    Toggle("효과 끄고 비교", isOn: Binding(
                        get: { !app.settings.output.effectsEnabled },
                        set: { app.settings.output.effectsEnabled = !$0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                OutputPreviewPanel(showsStats: showDebugOverlay)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                statusBar
            }
            .padding(16)
            .frame(minWidth: 480)
            Divider()
            panel
                .frame(width: 300)
        }
        .frame(minWidth: 980, minHeight: 600)
        .tint(Theme.accent)
    }

    private var sidebar: some View {
        VStack(spacing: 6) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon).font(.title3)
                        Text(item.title).font(.caption)
                    }
                    .frame(width: 64, height: 54)
                    .foregroundStyle(tab == item ? Theme.accent : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tab == item ? Theme.accent.opacity(0.12) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
            Spacer()
        }
        .padding(8)
    }

    @ViewBuilder private var panel: some View {
        switch tab {
        case .adjust:
            AdjustPanel()
        default:
            ContentUnavailableView(
                "\(tab.title) 준비 중",
                systemImage: tab.icon,
                description: Text("\(tab.stage)단계에서 추가될 예정이에요.")
            )
        }
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("내 화상 앱 화면은 좌우가 반전돼 보일 수 있지만, 상대방에게는 이 미리보기처럼 보여요.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(app.cameraStatus.inUse ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(app.virtualCameraSummary).font(.caption)
                Text("· 출력 \(app.outputFormat.description)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let message = app.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
        }
    }
}
