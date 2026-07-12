import AppKit
import SwiftUI

public struct PortableDeclarativeRuntimeView: View {
    public let app: TVAppProfile
    @State private var runtimeState: PortableDeclarativeRuntimeState
    private let allowedHosts: Set<String>

    public init(app: TVAppProfile) {
        self.app = app
        if case let .portableDeclarative(page, hosts) = app.target {
            _runtimeState = State(initialValue: PortableDeclarativeRuntimeState(page: page))
            allowedHosts = Set(hosts.map { $0.lowercased() })
        } else {
            let page = PortableDeclarativePage(title: app.name, sections: [])
            _runtimeState = State(initialValue: PortableDeclarativeRuntimeState(page: page))
            allowedHosts = []
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = TVMetrics(size: proxy.size)
            let columns = max(1, Int(proxy.size.width / (390 * metrics.scale)))

            TVOS18Backdrop(accent: Color(red: 0.16, green: 0.18, blue: 0.22))
                .overlay {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 34 * metrics.scale) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(runtimeState.page.title)
                                        .font(.system(size: 52 * metrics.scale, weight: .bold))
                                    Spacer()
                                    Text(runtimeState.statusText)
                                        .font(.system(size: 21 * metrics.scale, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .lineLimit(1)
                                }

                                ForEach(runtimeState.page.sections) { section in
                                    VStack(alignment: .leading, spacing: 18 * metrics.scale) {
                                        Text(section.title)
                                            .font(.system(size: 34 * metrics.scale, weight: .bold))
                                            .foregroundStyle(.white.opacity(0.84))

                                        LazyVGrid(
                                            columns: [GridItem(.adaptive(minimum: 330 * metrics.scale), spacing: 24 * metrics.scale)],
                                            alignment: .leading,
                                            spacing: 28 * metrics.scale
                                        ) {
                                            ForEach(section.cards) { card in
                                                let index = runtimeState.page.cards.firstIndex(where: { $0.id == card.id }) ?? 0
                                                TVOSMediaVideoCard(
                                                    title: card.title,
                                                    subtitle: card.subtitle,
                                                    metadata: "第三方宣告 UI",
                                                    imageURL: nil,
                                                    isFocused: index == runtimeState.focusedIndex,
                                                    metrics: metrics
                                                )
                                                .id("portable-card-\(index)")
                                            }
                                        }
                                    }
                                }

                                Text("方向鍵移動，OK 執行已簽章動作，Back 或 Home 返回。此畫面由 TVShell 原生繪製，不是網頁。")
                                    .font(.system(size: 22 * metrics.scale, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.58))
                            }
                            .padding(.horizontal, metrics.horizontalPadding)
                            .padding(.top, metrics.topPadding)
                            .padding(.bottom, 60 * metrics.scale)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: runtimeState.focusedIndex) { _, index in
                            withAnimation(TVMotion.focus) {
                                scrollProxy.scrollTo("portable-card-\(index)", anchor: .center)
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .tvShellRuntimeCommand)) { notification in
                            guard let command = notification.userInfo?[RuntimeCommandNotification.commandKey] as? RemoteCommand else { return }
                            let selectedAction = command == .select ? runtimeState.focusedCard?.action : nil
                            runtimeState.apply(command, columns: columns)
                            if let selectedAction, selectedAction.kind == .openURL {
                                openAllowedURL(selectedAction.value)
                            }
                        }
                    }
                }
        }
        .foregroundStyle(.white)
    }

    private func openAllowedURL(_ value: String) {
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host.map({ allowedHosts.contains($0.lowercased()) }) == true
        else { return }
        NSWorkspace.shared.open(url)
    }
}
