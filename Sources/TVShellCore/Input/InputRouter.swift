import AppKit
import GameController
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
    private let mappingCenter = RemoteMappingCenter.shared
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observesActivation = false
    private var controllerMonitor: GameControllerRemoteMonitor?
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
        guard let raw = AppKitRemoteEventTranslator.rawInput(from: event) else {
            return false
        }
        return handle(raw, isRepeat: event.isARepeat)
    }

    @discardableResult
    private func handle(_ raw: RawInputEvent, isRepeat: Bool = false) -> Bool {
        let wasCapturing = mappingCenter.captureTarget != nil
        guard let command = mappingCenter.command(for: raw) else {
            return wasCapturing
        }

        if command == .menu, case let .keyboard(keyCode, _, _) = raw {
            if isRepeat {
                cancelPendingMenu(for: keyCode)
                guard longPressDispatchedKeys.contains(keyCode) == false else { return true }
                longPressDispatchedKeys.insert(keyCode)
                dispatch(.longPress(.menu))
            } else {
                scheduleMenuDispatch(for: keyCode)
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
                  let command = self?.mappingCenter.command(for: raw)
            else {
                return
            }
            self?.dispatch(command)
        }

        if observesActivation == false {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidBecomeActive),
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
            observesActivation = true
        }

        if controllerMonitor == nil {
            let monitor = GameControllerRemoteMonitor { [weak self] raw in
                _ = self?.handle(raw)
            }
            controllerMonitor = monitor
            monitor.start()
        }
    }

    private func restartGlobalEventMonitor() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            guard let raw = AppKitRemoteEventTranslator.rawInput(from: event) else { return }
            _ = self?.handle(raw)
        }
    }

    @objc private func applicationDidBecomeActive() {
        restartGlobalEventMonitor()
        controllerMonitor?.refreshControllers()
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
        if observesActivation {
            NotificationCenter.default.removeObserver(
                self,
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
            observesActivation = false
        }
        controllerMonitor?.stop()
        controllerMonitor = nil
    }
}

@MainActor
private final class GameControllerRemoteMonitor: NSObject {
    private let onInput: (RawInputEvent) -> Void
    private var observesConnections = false

    init(onInput: @escaping (RawInputEvent) -> Void) {
        self.onInput = onInput
        super.init()
    }

    func start() {
        if observesConnections == false {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(controllerDidConnect),
                name: .GCControllerDidConnect,
                object: nil
            )
            observesConnections = true
        }
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        refreshControllers()
    }

    func stop() {
        if observesConnections {
            NotificationCenter.default.removeObserver(self, name: .GCControllerDidConnect, object: nil)
            observesConnections = false
        }
        GCController.stopWirelessControllerDiscovery()
    }

    func refreshControllers() {
        GCController.controllers().forEach(bind)
    }

    @objc private func controllerDidConnect() {
        refreshControllers()
    }

    private func bind(_ controller: GCController) {
        let profile = controller.physicalInputProfile
        if let dpad = profile.dpads[GCInputDirectionPad] {
            bind(dpad.up, to: .up)
            bind(dpad.down, to: .down)
            bind(dpad.left, to: .left)
            bind(dpad.right, to: .right)
        }
        bind(profile.buttons[GCInputButtonA], to: .primary)
        bind(profile.buttons[GCInputButtonB], to: .back)
        bind(profile.buttons[GCInputButtonMenu], to: .back)
        bind(profile.buttons[GCInputButtonHome], to: .home)
        bind(profile.buttons[GCInputButtonOptions], to: .menu)
        bind(profile.buttons[GCInputButtonX], to: .playPause)
    }

    private func bind(_ input: GCControllerButtonInput?, to button: GameControllerRemoteButton) {
        input?.pressedChangedHandler = { [weak self] _, _, isPressed in
            guard isPressed else { return }
            Task { @MainActor [weak self] in
                self?.onInput(GameControllerRemoteInput.rawInput(for: button))
            }
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
