import AppKit
import SwiftUI

public struct InputRouterView<Content: View>: NSViewRepresentable {
    private let content: Content
    private let onCommand: (RemoteCommand) -> Void

    public init(onCommand: @escaping (RemoteCommand) -> Void, @ViewBuilder content: () -> Content) {
        self.onCommand = onCommand
        self.content = content()
    }

    public func makeNSView(context: Context) -> HostingKeyView<Content> {
        let view = HostingKeyView(rootView: content)
        view.onCommand = onCommand
        return view
    }

    public func updateNSView(_ nsView: HostingKeyView<Content>, context: Context) {
        nsView.rootView = content
        nsView.onCommand = onCommand
    }
}

public final class HostingKeyView<Content: View>: NSHostingView<Content> {
    public var onCommand: ((RemoteCommand) -> Void)?
    private let mapper = KeyCodeMapper.default
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var longPressDispatchedKeys = Set<UInt16>()
    private var pendingMenuDispatches: [UInt16: DispatchWorkItem] = [:]

    public override var acceptsFirstResponder: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        if window == nil {
            stopEventMonitors()
        } else {
            startEventMonitors()
        }
    }

    public override func keyDown(with event: NSEvent) {
        if handle(event) {
            return
        }
        super.keyDown(with: event)
    }

    public override func keyUp(with event: NSEvent) {
        dispatchPendingMenuIfNeeded(for: event.keyCode)
        longPressDispatchedKeys.remove(event.keyCode)
        super.keyUp(with: event)
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard let raw = AppKitRemoteEventTranslator.rawInput(from: event),
              let command = mapper.command(for: raw)
        else {
            return false
        }

        if command == .menu {
            if event.isARepeat {
                cancelPendingMenu(for: event.keyCode)
                guard longPressDispatchedKeys.contains(event.keyCode) == false else {
                    return true
                }
                longPressDispatchedKeys.insert(event.keyCode)
                dispatch(.longPress(.menu))
            } else {
                scheduleMenuDispatch(for: event.keyCode)
            }
            return true
        }
        dispatch(command)
        return true
    }

    private func scheduleMenuDispatch(for keyCode: UInt16) {
        guard pendingMenuDispatches[keyCode] == nil else {
            return
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.longPressDispatchedKeys.contains(keyCode) == false else {
                return
            }
            self.pendingMenuDispatches[keyCode] = nil
            self.dispatch(.menu)
        }
        pendingMenuDispatches[keyCode] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: item)
    }

    private func cancelPendingMenu(for keyCode: UInt16) {
        pendingMenuDispatches.removeValue(forKey: keyCode)?.cancel()
    }

    private func dispatchPendingMenuIfNeeded(for keyCode: UInt16) {
        let hadPendingMenu = pendingMenuDispatches[keyCode] != nil
        cancelPendingMenu(for: keyCode)
        if hadPendingMenu, longPressDispatchedKeys.contains(keyCode) == false {
            dispatch(.menu)
        }
    }

    private func dispatch(_ command: RemoteCommand) {
        DispatchQueue.main.async(execute: { [weak self] in
            self?.onCommand?(command)
        })
    }

    private func startEventMonitors() {
        guard localMonitor == nil, globalMonitor == nil else {
            return
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .systemDefined]) { [weak self] event in
            if event.type == .keyUp {
                self?.longPressDispatchedKeys.remove(event.keyCode)
                return event
            }
            guard self?.handle(event) == true else {
                return event
            }
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            guard let raw = AppKitRemoteEventTranslator.rawInput(from: event),
                  let command = KeyCodeMapper.default.command(for: raw)
            else {
                return
            }
            self?.dispatch(command)
        }
    }

    private func stopEventMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }
}

public extension RemoteModifier {
    static func from(_ flags: NSEvent.ModifierFlags) -> Set<RemoteModifier> {
        var modifiers: Set<RemoteModifier> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
