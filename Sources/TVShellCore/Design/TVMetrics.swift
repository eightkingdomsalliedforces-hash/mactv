import CoreGraphics

public struct TVMetrics: Equatable, Sendable {
    public let size: CGSize
    private let interfaceScale: Double

    public init(size: CGSize, interfaceScale: Double = 1) {
        self.size = size
        self.interfaceScale = min(max(interfaceScale, 0.8), 2)
    }

    public var scale: Double {
        let widthScale = size.width / 1920
        let heightScale = size.height / 1080
        return min(max(min(widthScale, heightScale), 0.72), 1.65) * interfaceScale
    }

    public var horizontalPadding: Double { 86 * scale }
    public var topPadding: Double { 48 * scale }
    public var rowSpacing: Double { 32 * scale }
    public var cardSpacing: Double { 42 * scale }
    public var heroTitleSize: Double { 82 * scale }
    public var heroSubtitleSize: Double { 30 * scale }
    public var rowTitleSize: Double { 30 * scale }
    public var hintSize: Double { 26 * scale }
    public var appIconSize: Double { 220 * scale }
    public var appTileWidth: Double { 222 * scale }
    public var appTileHeight: Double { appTileWidth / 1.55 }
    public var systemRowHeight: Double { 72 * scale }
    public var appTitleSize: Double { 34 * scale }
    public var appTitleWidth: Double { 260 * scale }
}
