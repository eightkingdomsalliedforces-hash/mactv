import SwiftUI

public struct AnimeSourceManagementView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let scale = max(0.82, min(proxy.size.width / 1920, 1.45))

            ZStack {
                TVControlBackdrop()

                VStack(alignment: .leading, spacing: 28 * scale) {
                    header(scale: scale)

                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 16 * scale) {
                                ForEach(appState.animeSourceCatalog.instances) { source in
                                    AnimeSourceRow(
                                        source: source,
                                        isFocused: source.id == appState.focusedAnimeSourceID,
                                        mode: appState.animeSourceCatalog.displayMode,
                                        scale: scale
                                    )
                                    .id(source.id)
                                }
                            }
                            .padding(.vertical, 8 * scale)
                        }
                        .onChange(of: appState.focusedAnimeSourceID) { _, id in
                            guard let id else {
                                return
                            }
                            withAnimation(TVMotion.focus) {
                                scrollProxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }

                    Text("上下選來源，左右切線路，OK 啟用或停用，Menu 切換模式，上一首/下一首調整排序。")
                        .font(.system(size: 25 * scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 72 * scale)
                .padding(.vertical, 54 * scale)
            }
        }
    }

    private func header(scale: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 28 * scale) {
            VStack(alignment: .leading, spacing: 10 * scale) {
                Text("動漫來源")
                    .font(.system(size: 72 * scale, weight: .bold))
                Text("Animeko 風格解析來源與線路管理")
                    .font(.system(size: 28 * scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
            }

            Spacer()

            AnimeSourceModePill(mode: appState.animeSourceCatalog.displayMode, scale: scale)
        }
    }
}

private struct AnimeSourceModePill: View {
    let mode: AnimeSourceDisplayMode
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            segment("簡單模式", isSelected: mode == .simple)
            segment("詳細模式", isSelected: mode == .detailed)
        }
        .padding(4 * scale)
        .background(
            Capsule()
                .fill(.white.opacity(0.08))
        )
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.28), lineWidth: 1)
        )
    }

    private func segment(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.system(size: 24 * scale, weight: .bold))
            .foregroundStyle(isSelected ? .white : .white.opacity(0.58))
            .padding(.horizontal, 30 * scale)
            .padding(.vertical, 14 * scale)
            .background(
                Capsule()
                    .fill(isSelected ? .white.opacity(0.20) : .clear)
            )
    }
}

private struct AnimeSourceRow: View {
    let source: AnimeSourceInstance
    let isFocused: Bool
    let mode: AnimeSourceDisplayMode
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 24 * scale) {
            Text(source.definition.iconLabel)
                .font(.system(size: 25 * scale, weight: .heavy, design: .rounded))
                .frame(width: 58 * scale, height: 58 * scale)
                .background(Circle().fill(iconColor.opacity(source.isEnabled ? 0.92 : 0.36)))
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))

            VStack(alignment: .leading, spacing: 9 * scale) {
                HStack(spacing: 16 * scale) {
                    Text(source.definition.title)
                        .font(.system(size: 32 * scale, weight: .bold))
                        .foregroundStyle(source.isEnabled ? .white : .white.opacity(0.46))
                    AnimeSourceHealthBadge(health: source.definition.health, isEnabled: source.isEnabled, scale: scale)
                }

                if mode == .detailed {
                    Text(detailText)
                        .font(.system(size: 21 * scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                }
            }
            .frame(minWidth: 280 * scale, alignment: .leading)

            Spacer(minLength: 20 * scale)

            FlowLineChips(source: source, scale: scale)
        }
        .padding(.horizontal, 26 * scale)
        .padding(.vertical, 18 * scale)
        .scaleEffect(isFocused ? 1.022 : 1.0)
        .liquidGlassCard(isFocused: isFocused, cornerRadius: 28 * scale)
        .opacity(source.isEnabled ? 1 : 0.62)
        .animation(TVMotion.focus, value: isFocused)
        .animation(TVMotion.focus, value: source.selectedLineID)
        .animation(TVMotion.focus, value: source.isEnabled)
    }

    private var iconColor: Color {
        switch source.definition.health {
        case .available: .green
        case .loading: .white.opacity(0.62)
        case .needsCloudflare, .needsCaptcha: .orange
        case .needsAdapter: .yellow
        case .failed: .red
        case .disabled: .gray
        }
    }

    private var detailText: String {
        if source.definition.isAdult {
            return "成人來源，預設關閉"
        }

        switch source.definition.health {
        case .available:
            return "可解析，已選線路：\(source.selectedLine?.title ?? "預設")"
        case .loading:
            return "正在等待解析器健康檢查"
        case .needsCloudflare:
            return "需要先在驗證視窗通過 Cloudflare"
        case .needsCaptcha:
            return "需要先處理驗證碼"
        case .needsAdapter:
            return "尚未接入合法 adapter；可改用官方 API、Selector JSON 或自有媒體服務"
        case .failed:
            return "目前不可用，可稍後重試"
        case .disabled:
            return "已停用"
        }
    }
}

private struct AnimeSourceHealthBadge: View {
    let health: AnimeSourceHealth
    let isEnabled: Bool
    let scale: CGFloat

    var body: some View {
        Text(title)
            .font(.system(size: 18 * scale, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 7 * scale)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().stroke(color.opacity(0.34), lineWidth: 1))
    }

    private var title: String {
        guard isEnabled else {
            return "已停用"
        }

        switch health {
        case .loading: return "載入中"
        case .available: return "可用"
        case .failed: return "失敗"
        case .needsCloudflare: return "Cloudflare"
        case .needsCaptcha: return "驗證碼"
        case .needsAdapter: return "待接入"
        case .disabled: return "已停用"
        }
    }

    private var color: Color {
        guard isEnabled else {
            return .white.opacity(0.48)
        }

        switch health {
        case .loading: return .white.opacity(0.62)
        case .available: return .green
        case .failed: return .red
        case .needsCloudflare, .needsCaptcha: return .orange
        case .needsAdapter: return .yellow
        case .disabled: return .white.opacity(0.48)
        }
    }
}

private struct FlowLineChips: View {
    let source: AnimeSourceInstance
    let scale: CGFloat

    var body: some View {
        FlexibleHStack(spacing: 10 * scale) {
            ForEach(source.definition.lines) { line in
                LineChip(
                    title: line.title,
                    isSelected: line.id == source.selectedLine?.id,
                    isDeprecated: line.isDeprecated,
                    scale: scale
                )
            }
        }
        .frame(maxWidth: 660 * scale, alignment: .trailing)
    }
}

private struct LineChip: View {
    let title: String
    let isSelected: Bool
    let isDeprecated: Bool
    let scale: CGFloat

    var body: some View {
        Text(title)
            .font(.system(size: 22 * scale, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 17 * scale)
            .padding(.vertical, 10 * scale)
            .background(
                Capsule()
                    .fill(isSelected ? .white.opacity(0.22) : .white.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? .white.opacity(0.56) : .white.opacity(0.18), lineWidth: isSelected ? 2 : 1)
            )
    }

    private var foreground: Color {
        if isDeprecated {
            return .white.opacity(0.38)
        }
        return isSelected ? .white : .white.opacity(0.66)
    }
}

private struct FlexibleHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
    }
}
