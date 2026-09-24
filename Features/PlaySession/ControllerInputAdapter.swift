#if canImport(UIKit)
import Foundation
import GameController

/// Observes standard extended gamepads and reports complete per-controller button sets.
@MainActor
public final class ControllerInputAdapter {
    public var onButtons: (Set<DSButton>, String) -> Void
    public var onDisconnect: (String) -> Void
    private var connected: [ObjectIdentifier: GCController] = [:]
    private var observers: [NSObjectProtocol] = []

    public init(onButtons: @escaping (Set<DSButton>, String) -> Void,
                onDisconnect: @escaping (String) -> Void) {
        self.onButtons = onButtons
        self.onDisconnect = onDisconnect
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidConnect,
                                                                  object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.connect(controller) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect,
                                                                  object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.disconnect(controller) }
        })
        for controller in GCController.controllers() { connect(controller) }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        for controller in connected.values { controller.extendedGamepad?.valueChangedHandler = nil }
    }

    private func source(_ controller: GCController) -> String {
        String(describing: ObjectIdentifier(controller))
    }

    private func connect(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        connected[ObjectIdentifier(controller)] = controller
        pad.valueChangedHandler = { [weak self, weak controller] _, _ in
            guard let controller else { return }
            Task { @MainActor in self?.publish(controller) }
        }
        publish(controller)
    }

    private func disconnect(_ controller: GCController) {
        connected.removeValue(forKey: ObjectIdentifier(controller))
        controller.extendedGamepad?.valueChangedHandler = nil
        onDisconnect(source(controller))
    }

    private func publish(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        var buttons = Set<DSButton>()
        if pad.buttonA.isPressed { buttons.insert(.a) }
        if pad.buttonB.isPressed { buttons.insert(.b) }
        if pad.buttonX.isPressed { buttons.insert(.x) }
        if pad.buttonY.isPressed { buttons.insert(.y) }
        if pad.leftShoulder.isPressed { buttons.insert(.l) }
        if pad.rightShoulder.isPressed { buttons.insert(.r) }
        if pad.buttonMenu.isPressed { buttons.insert(.start) }
        if pad.buttonOptions?.isPressed == true { buttons.insert(.select) }
        if pad.dpad.up.isPressed || pad.leftThumbstick.yAxis.value > 0.5 { buttons.insert(.up) }
        if pad.dpad.down.isPressed || pad.leftThumbstick.yAxis.value < -0.5 { buttons.insert(.down) }
        if pad.dpad.left.isPressed || pad.leftThumbstick.xAxis.value < -0.5 { buttons.insert(.left) }
        if pad.dpad.right.isPressed || pad.leftThumbstick.xAxis.value > 0.5 { buttons.insert(.right) }
        onButtons(buttons, source(controller))
    }
}
#endif
