import SwiftUI
import UniformTypeIdentifiers

public struct AppManagementView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isImporterPresented = false
    @State private var pendingTrustPackage: VerifiedPortableApp?
    @State private var installError: String?

    public init() {}

    public var body: some View {
        ZStack {
            TVOS18Backdrop(accent: Color(red: 0.18, green: 0.20, blue: 0.22))

            GeometryReader { proxy in
                let metrics = TVMetrics(size: proxy.size)

                TVOS18SettingsSplitView(metrics: metrics) {
                    TVOS18SettingsSidebar(
                        symbolName: "square.grid.2x2.fill",
                        title: "App 管理",
                        subtitle: "Menu 安裝 .tvshellapp；長按 OK 移除第三方 App。上下選擇，OK 顯示或隱藏，左右調整順序。",
                        metrics: metrics
                    )
                } content: {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 12 * metrics.scale) {
                                ForEach(appState.apps) { app in
                                    AppManagementRow(
                                        app: app,
                                        isFocused: app.id == appState.focusedManagementAppID,
                                        metrics: metrics
                                    )
                                    .id(app.id)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: proxy.size.height - 120 * metrics.scale, alignment: .topLeading)
                            .padding(.horizontal, 10 * metrics.scale)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: appState.focusedManagementAppID) { _, id in
                            guard let id else { return }
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
            }
        }
        .foregroundStyle(.white)
        .onReceive(NotificationCenter.default.publisher(for: .tvShellRequestPortableAppImporter)) { _ in
            isImporterPresented = true
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.package],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let package = try appState.inspectPortableApp(at: url)
                do {
                    try appState.installPortableApp(package, trustingNewDeveloper: false)
                } catch PortableAppPackageError.untrustedDeveloper {
                    pendingTrustPackage = package
                }
            } catch {
                installError = error.localizedDescription
            }
        }
        .alert(
            "信任並安裝第三方 App？",
            isPresented: Binding(
                get: { pendingTrustPackage != nil },
                set: { if $0 == false { pendingTrustPackage = nil } }
            ),
            presenting: pendingTrustPackage
        ) { package in
            Button("信任並安裝") {
                do { try appState.installPortableApp(package, trustingNewDeveloper: true) }
                catch { installError = error.localizedDescription }
                pendingTrustPackage = nil
            }
            Button("取消", role: .cancel) { pendingTrustPackage = nil }
        } message: { package in
            Text("\(package.manifest.name) \(package.manifest.version)\n開發者指紋：\(package.developerFingerprint)")
        }
        .alert(
            "無法安裝 App",
            isPresented: Binding(
                get: { installError != nil },
                set: { if $0 == false { installError = nil } }
            )
        ) {
            Button("好") { installError = nil }
        } message: {
            Text(installError ?? "未知錯誤")
        }
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
                .background(.black.opacity(isFocused ? 0.10 : 0.22), in: RoundedRectangle(cornerRadius: 12 * metrics.scale, style: .continuous))

            Text(app.name)
                .font(.system(size: 34 * metrics.scale, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.66)

            Spacer()

            Text(app.isVisibleOnHome ? "顯示" : "隱藏")
                .font(.system(size: 28 * metrics.scale, weight: .medium))
                .foregroundStyle(
                    isFocused
                        ? .black.opacity(0.62)
                        : (app.isVisibleOnHome ? .green.opacity(0.9) : .white.opacity(0.46))
                )
        }
        .padding(.horizontal, 26 * metrics.scale)
        .padding(.vertical, 18 * metrics.scale)
        .tvOS18Surface(role: .row, isFocused: isFocused, cornerRadius: 10 * metrics.scale)
    }
}
