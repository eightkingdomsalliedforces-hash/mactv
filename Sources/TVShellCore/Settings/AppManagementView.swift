import SwiftUI

public struct AppManagementView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let metrics = TVMetrics(size: proxy.size)

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 34 * metrics.scale) {
                        Text("App 管理")
                            .font(.system(size: 72 * metrics.scale, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)

                        Text("上下選擇，OK 顯示或隱藏，左右排序，Home 返回。")
                            .font(.system(size: 28 * metrics.scale, weight: .medium))
                            .foregroundStyle(.white.opacity(0.66))
                            .lineLimit(2)
                            .minimumScaleFactor(0.74)

                        VStack(alignment: .leading, spacing: 18 * metrics.scale) {
                            ForEach(appState.apps) { app in
                                AppManagementRow(
                                    app: app,
                                    isFocused: app.id == appState.focusedManagementAppID,
                                    metrics: metrics
                                )
                                .id(app.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, max(34, metrics.topPadding))
                }
                .scrollIndicators(.hidden)
                .onChange(of: appState.focusedManagementAppID) { _, id in
                    guard let id else {
                        return
                    }
                    withAnimation(TVMotion.focus) {
                        scrollProxy.scrollTo(id, anchor: .center)
                    }
                }
                .onAppear {
                    if let id = appState.focusedManagementAppID {
                        scrollProxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }
}

private struct AppManagementRow: View {
    let app: TVAppProfile
    let isFocused: Bool
    let metrics: TVMetrics

    var body: some View {
        HStack(spacing: 24 * metrics.scale) {
            Text(String(app.name.prefix(1)))
                .font(.system(size: 38 * metrics.scale, weight: .bold, design: .rounded))
                .frame(width: 74 * metrics.scale, height: 74 * metrics.scale)
                .liquidGlassCard(isFocused: isFocused, cornerRadius: 20 * metrics.scale)

            Text(app.name)
                .font(.system(size: 34 * metrics.scale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.66)

            Spacer()

            Text(app.isVisibleOnHome ? "顯示" : "隱藏")
                .font(.system(size: 28 * metrics.scale, weight: .medium))
                .foregroundStyle(app.isVisibleOnHome ? .green.opacity(0.9) : .white.opacity(0.46))
        }
        .padding(.horizontal, 26 * metrics.scale)
        .padding(.vertical, 18 * metrics.scale)
        .liquidGlassCard(isFocused: isFocused, cornerRadius: 24 * metrics.scale)
    }
}
