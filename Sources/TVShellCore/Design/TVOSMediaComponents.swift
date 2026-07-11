import SwiftUI

public struct TVOSMediaNavigationItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let symbolName: String?

    public init(id: String, title: String, symbolName: String? = nil) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
    }
}

public struct TVOSMediaTopNavigation: View {
    public let items: [TVOSMediaNavigationItem]
    public let focusedID: String
    public let metrics: TVMetrics

    public init(items: [TVOSMediaNavigationItem], focusedID: String, metrics: TVMetrics) {
        self.items = items
        self.focusedID = focusedID
        self.metrics = metrics
    }

    public var body: some View {
        HStack(spacing: 5 * metrics.scale) {
            ForEach(items) { item in
                let isFocused = item.id == focusedID
                HStack(spacing: 8 * metrics.scale) {
                    if let symbolName = item.symbolName {
                        Image(systemName: symbolName)
                    }
                    Text(item.title)
                }
                .font(.system(size: 24 * metrics.scale, weight: .bold))
                .foregroundStyle(isFocused ? .black : .white.opacity(0.62))
                .padding(.horizontal, 24 * metrics.scale)
                .frame(height: 52 * metrics.scale)
                .background(isFocused ? Color.white.opacity(0.92) : .clear)
                .clipShape(Capsule())
            }
        }
        .padding(5 * metrics.scale)
        .background(.black.opacity(0.72))
        .clipShape(Capsule())
        .animation(TVMotion.focus, value: focusedID)
    }
}

public struct TVOSMediaVideoCard: View {
    public let title: String
    public let subtitle: String?
    public let metadata: String?
    public let imageURL: URL?
    public let isFocused: Bool
    public let metrics: TVMetrics

    public init(title: String, subtitle: String? = nil, metadata: String? = nil, imageURL: URL? = nil, isFocused: Bool, metrics: TVMetrics) {
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.imageURL = imageURL
        self.isFocused = isFocused
        self.metrics = metrics
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9 * metrics.scale) {
            AsyncImage(url: imageURL) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 44 * metrics.scale, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12 * metrics.scale, style: .continuous))
            .tvOS18ContentFocus(isFocused: isFocused)

            Text(title)
                .font(.system(size: 23 * metrics.scale, weight: .bold))
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 19 * metrics.scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
            if let metadata {
                Text(metadata)
                    .font(.system(size: 17 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .scaleEffect(isFocused ? 1.045 : 1)
        .animation(TVMotion.focus, value: isFocused)
    }
}

public struct TVOSMediaHero<Actions: View>: View {
    public let eyebrow: String
    public let title: String
    public let subtitle: String?
    public let description: String
    public let imageURL: URL?
    public let metrics: TVMetrics
    private let actions: Actions

    public init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        description: String,
        imageURL: URL? = nil,
        metrics: TVMetrics,
        @ViewBuilder actions: () -> Actions
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.imageURL = imageURL
        self.metrics = metrics
        self.actions = actions()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 46 * metrics.scale) {
            AsyncImage(url: imageURL) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.07)
                        Image(systemName: "film.stack.fill")
                            .font(.system(size: 58 * metrics.scale, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.34))
                    }
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .frame(width: 280 * metrics.scale)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14 * metrics.scale, style: .continuous))

            VStack(alignment: .leading, spacing: 18 * metrics.scale) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 18 * metrics.scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.48))
                Text(title)
                    .font(.system(size: 54 * metrics.scale, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.system(size: 24 * metrics.scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
                Text(description)
                    .font(.system(size: 24 * metrics.scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(7)
                actions
                    .padding(.top, 8 * metrics.scale)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

public struct TVOSMediaEmptyState: View {
    public let title: String
    public let message: String
    public let isLoading: Bool
    public let metrics: TVMetrics

    public init(title: String, message: String, isLoading: Bool = false, metrics: TVMetrics) {
        self.title = title
        self.message = message
        self.isLoading = isLoading
        self.metrics = metrics
    }

    public var body: some View {
        VStack(spacing: 18 * metrics.scale) {
            if isLoading {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: "rectangle.stack.badge.questionmark")
                    .font(.system(size: 58 * metrics.scale, weight: .medium))
            }
            Text(title).font(.system(size: 34 * metrics.scale, weight: .bold))
            Text(message)
                .font(.system(size: 22 * metrics.scale, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 320 * metrics.scale)
    }
}
