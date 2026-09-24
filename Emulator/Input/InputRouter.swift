// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import Foundation
import CoreGraphics

/// Main-thread input accumulator. Each producer owns its source identifier, so releasing one
/// controller or finger cannot release a button still held by another producer.
public final class InputRouter {
    private var heldButtons: [String: Set<DSButton>] = [:]
    private var stylusID: UInt64?
    private var stylusPoint: CGPoint?
    private var lowerScreen = CGRect(x: 0, y: 0, width: 0, height: 0)

    public init() {}

    public var snapshot: DSInput {
        var result = DSInput()
        for buttons in heldButtons.values {
            for button in buttons { result.buttons |= UInt16(1) << UInt16(button.rawValue) }
        }
        if let point = stylusPoint, let mapped = Self.mapTouch(point, in: lowerScreen) {
            result.touching = true
            result.touchX = mapped.x
            result.touchY = mapped.y
        }
        return result
    }

    public func press(_ button: DSButton, source: String) {
        heldButtons[source, default: []].insert(button)
    }

    public func release(_ button: DSButton, source: String) {
        heldButtons[source]?.remove(button)
        if heldButtons[source]?.isEmpty == true { heldButtons.removeValue(forKey: source) }
    }

    public func setButtons(_ buttons: Set<DSButton>, source: String) {
        if buttons.isEmpty { heldButtons.removeValue(forKey: source) }
        else { heldButtons[source] = buttons }
    }

    public func disconnect(source: String) { heldButtons.removeValue(forKey: source) }

    /// Captures only the first contact that begins on the rendered lower screen.
    @discardableResult
    public func beginStylus(id: UInt64, at point: CGPoint, lowerScreen: CGRect) -> Bool {
        guard stylusID == nil, Self.mapTouch(point, in: lowerScreen) != nil else { return false }
        stylusID = id
        stylusPoint = point
        self.lowerScreen = lowerScreen
        return true
    }

    public func moveStylus(id: UInt64, to point: CGPoint) {
        guard stylusID == id else { return }
        // A drag outside releases native touch, while retaining contact identity until lift.
        stylusPoint = Self.mapTouch(point, in: lowerScreen) == nil ? nil : point
    }

    public func endStylus(id: UInt64) {
        guard stylusID == id else { return }
        stylusID = nil
        stylusPoint = nil
    }

    /// Geometry changes invalidate the captured screen and contact transform.
    public func setLowerScreen(_ rect: CGRect) {
        guard !rect.duoEquals(lowerScreen) else { return }
        lowerScreen = rect
        stylusID = nil
        stylusPoint = nil
    }

    /// Called for scene loss, pause, touch cancellation and app interruption.
    public func cancelTransientInputs() {
        heldButtons.removeAll()
        stylusID = nil
        stylusPoint = nil
    }

    public static func mapTouch(_ point: CGPoint, in rect: CGRect) -> (x: UInt16, y: UInt16)? {
        guard rect.width > 0, rect.height > 0,
              point.x.isFinite, point.y.isFinite,
              point.x >= rect.minX, point.x < rect.maxX,
              point.y >= rect.minY, point.y < rect.maxY else { return nil }
        let x = min(255, max(0, Int((point.x - rect.minX) * 256 / rect.width)))
        let y = min(191, max(0, Int((point.y - rect.minY) * 192 / rect.height)))
        return (UInt16(x), UInt16(y))
    }
}
