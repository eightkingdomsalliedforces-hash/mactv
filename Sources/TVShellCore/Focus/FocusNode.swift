import CoreGraphics

public struct FocusNode: Equatable, Sendable {
    public let id: FocusID
    public let rect: CGRect
    public let group: FocusGroupID
    public let priority: Int
    public let acceptsSelect: Bool
    public let acceptsLongPress: Bool

    public init(
        id: FocusID,
        rect: CGRect,
        group: FocusGroupID,
        priority: Int,
        acceptsSelect: Bool,
        acceptsLongPress: Bool = false
    ) {
        self.id = id
        self.rect = rect
        self.group = group
        self.priority = priority
        self.acceptsSelect = acceptsSelect
        self.acceptsLongPress = acceptsLongPress
    }
}
