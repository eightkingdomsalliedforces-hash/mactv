import Foundation
import SwiftUI

@MainActor
public final class RemoteMappingCenter: ObservableObject {
    public static let shared = RemoteMappingCenter.applicationSupport()

    @Published public private(set) var captureTarget: RemoteCommand?
    @Published public private(set) var lastRawEventDescription = "尚未收到原始按鍵"
    @Published public private(set) var lastCapturedCommand: RemoteCommand?
    @Published public private(set) var statusText = "選擇指令後按 OK，再按要綁定的遙控器按鍵。"

    public let fileURL: URL
    private var store: RemoteMappingStore

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(RemoteMappingStore.self, from: data) {
            store = decoded
        } else {
            store = RemoteMappingStore()
        }
    }

    public static func applicationSupport() -> RemoteMappingCenter {
        let root = TVShellStorageMigration.resolvedApplicationSupportDirectory()
        return RemoteMappingCenter(fileURL: root.appendingPathComponent("remote-mappings.json"))
    }

    public var learnedMappingCount: Int {
        store.learnedMappingCount
    }

    public func armCapture(for command: RemoteCommand) {
        captureTarget = command
        statusText = "等待遙控器按鍵：\(command.description)"
    }

    public func cancelCapture() {
        captureTarget = nil
        statusText = "已取消按鍵學習。"
    }

    public func command(for event: RawInputEvent) -> RemoteCommand? {
        lastRawEventDescription = Self.describe(event)
        if let target = captureTarget {
            store.learn(event, as: target)
            captureTarget = nil
            lastCapturedCommand = target
            persist()
            statusText = "已綁定 \(Self.describe(event)) → \(target.description)"
            return nil
        }
        return store.command(for: event)
    }

    public func reset() {
        captureTarget = nil
        lastCapturedCommand = nil
        store.reset()
        persist()
        statusText = "已清除全部自定義按鍵。"
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(store).write(to: fileURL, options: .atomic)
        } catch {
            statusText = "按鍵設定儲存失敗：\(error.localizedDescription)"
        }
    }

    private static func describe(_ event: RawInputEvent) -> String {
        switch event {
        case let .keyboard(keyCode, characters, modifiers):
            let text = characters?.isEmpty == false ? " \(characters!)" : ""
            let modifierText = modifiers.isEmpty ? "" : " \(modifiers.map(\.rawValue).sorted().joined(separator: "+"))"
            return "Keyboard \(keyCode)\(text)\(modifierText)"
        case let .media(systemCode):
            return "Media \(systemCode)"
        case let .hid(usagePage, usage):
            return String(format: "HID %02X:%03X", usagePage, usage)
        }
    }
}
