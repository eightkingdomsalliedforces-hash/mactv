import SwiftUI

public struct VirtualKeyboardView: View {
    public let title: String
    public let state: VirtualKeyboardState
    public let metrics: TVMetrics

    public init(title: String, state: VirtualKeyboardState, metrics: TVMetrics) {
        self.title = title
        self.state = state
        self.metrics = metrics
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22 * metrics.scale) {
                HStack {
                    Text(title)
                        .font(.system(size: 42 * metrics.scale, weight: .bold))
                    Spacer()
                    Text(state.layout.title)
                        .font(.system(size: 24 * metrics.scale, weight: .bold))
                        .padding(.horizontal, 18 * metrics.scale)
                        .padding(.vertical, 10 * metrics.scale)
                        .liquidGlassCard(isFocused: false, cornerRadius: 16 * metrics.scale)
                }

                Text(state.text.isEmpty ? "輸入搜尋內容" : state.text)
                    .font(.system(size: 48 * metrics.scale, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.48)
                    .frame(maxWidth: .infinity, minHeight: 78 * metrics.scale, alignment: .leading)
                    .padding(.horizontal, 28 * metrics.scale)
                    .padding(.vertical, 18 * metrics.scale)
                    .liquidGlassCard(isFocused: true, cornerRadius: 24 * metrics.scale)

                VStack(alignment: .leading, spacing: 14 * metrics.scale) {
                    ForEach(Array(state.rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 12 * metrics.scale) {
                            ForEach(Array(row.enumerated()), id: \.element.id) { columnIndex, key in
                                Text(key.label)
                                    .font(.system(size: 28 * metrics.scale, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.62)
                                    .frame(width: keyWidth(for: key), height: 62 * metrics.scale)
                                    .liquidGlassCard(
                                        isFocused: rowIndex == state.focusedRow && columnIndex == state.focusedColumn,
                                        cornerRadius: 20 * metrics.scale
                                    )
                            }
                        }
                    }
                }

                Text("方向鍵選字，OK 輸入，Back 刪除，搜尋鍵提交。")
                    .font(.system(size: 22 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .foregroundStyle(.white)
            .padding(36 * metrics.scale)
                    .frame(maxWidth: 1120 * metrics.scale)
            .liquidGlassCard(isFocused: true, cornerRadius: 34 * metrics.scale)
            .padding(.horizontal, 56 * metrics.scale)
        }
    }

    private func keyWidth(for key: VirtualKeyboardKey) -> Double {
        switch key.kind {
        case .character:
            68 * metrics.scale
        case .space:
            150 * metrics.scale
        case .delete, .submit, .cancel, .layoutSwitch:
            132 * metrics.scale
        }
    }
}
