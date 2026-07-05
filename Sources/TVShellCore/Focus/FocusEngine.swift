import CoreGraphics

public struct FocusEngine: Sendable {
    private var nodesByID: [FocusID: FocusNode] = [:]
    private var currentID: FocusID?

    public init() {}

    public var currentFocus: FocusID? {
        currentID
    }

    public mutating func register(_ nodes: [FocusNode]) {
        nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        if let currentID, nodesByID[currentID] == nil {
            self.currentID = nil
        }
    }

    public mutating func setFocus(_ id: FocusID?) {
        guard let id else {
            currentID = nil
            return
        }

        if nodesByID[id] != nil {
            currentID = id
        }
    }

    @discardableResult
    public mutating func move(_ direction: FocusDirection) -> FocusID? {
        guard let currentID, let current = nodesByID[currentID] else {
            return recoverFocus(in: nil)
        }

        let candidates = nodesByID.values.filter { node in
            node.id != current.id
                && node.group == current.group
                && isCandidate(node.rect, from: current.rect, direction: direction)
        }

        guard let next = candidates.min(by: {
            score($0.rect, from: current.rect, direction: direction)
                < score($1.rect, from: current.rect, direction: direction)
        }) else {
            return currentID
        }

        self.currentID = next.id
        return next.id
    }

    @discardableResult
    public mutating func recoverFocus(in group: FocusGroupID?) -> FocusID? {
        let candidates = nodesByID.values.filter { group == nil || $0.group == group }
        guard let recovered = candidates.sorted(by: {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.rect.minY != $1.rect.minY { return $0.rect.minY < $1.rect.minY }
            return $0.rect.minX < $1.rect.minX
        }).first else {
            currentID = nil
            return nil
        }

        currentID = recovered.id
        return recovered.id
    }

    private func isCandidate(_ candidate: CGRect, from current: CGRect, direction: FocusDirection) -> Bool {
        switch direction {
        case .up: return candidate.midY < current.midY
        case .down: return candidate.midY > current.midY
        case .left: return candidate.midX < current.midX
        case .right: return candidate.midX > current.midX
        }
    }

    private func score(_ candidate: CGRect, from current: CGRect, direction: FocusDirection) -> CGFloat {
        let primary: CGFloat
        let secondary: CGFloat

        switch direction {
        case .up:
            primary = current.midY - candidate.midY
            secondary = abs(current.midX - candidate.midX)
        case .down:
            primary = candidate.midY - current.midY
            secondary = abs(current.midX - candidate.midX)
        case .left:
            primary = current.midX - candidate.midX
            secondary = abs(current.midY - candidate.midY)
        case .right:
            primary = candidate.midX - current.midX
            secondary = abs(current.midY - candidate.midY)
        }

        return primary * 10_000 + secondary
    }
}
