public struct RemoteMappingStore: Codable, Equatable, Sendable {
    private var learnedMappings: [RawInputEvent: RemoteCommand]
    private var fallbackMapper: KeyCodeMapper

    public init(
        learnedMappings: [RawInputEvent: RemoteCommand] = [:],
        fallbackMapper: KeyCodeMapper = .default
    ) {
        self.learnedMappings = learnedMappings
        self.fallbackMapper = fallbackMapper
    }

    enum CodingKeys: String, CodingKey {
        case learnedMappings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        learnedMappings = try container.decode([RawInputEvent: RemoteCommand].self, forKey: .learnedMappings)
        fallbackMapper = .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(learnedMappings, forKey: .learnedMappings)
    }

    public mutating func learn(_ event: RawInputEvent, as command: RemoteCommand) {
        learnedMappings[event] = command
    }

    public func command(for event: RawInputEvent) -> RemoteCommand? {
        learnedMappings[event] ?? fallbackMapper.command(for: event)
    }
}
