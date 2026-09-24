// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import Foundation

public enum DSButton: Int, CaseIterable, Sendable {
    // libretro joypad IDs; do not reorder.
    case b = 0, y = 1, select = 2, start = 3, up = 4, down = 5, left = 6, right = 7, a = 8, x = 9, l = 10, r = 11
}
public struct DSInput: Equatable, Sendable {
    public var buttons: UInt16 = 0
    public var touchX: UInt16 = 0
    public var touchY: UInt16 = 0
    public var touching: Bool = false
    public init() {}
}
public struct DSFrame: Sendable {
    public let pixels: Data // owned BGRA8, tightly packed; top 256x192 then lower 256x192
    public let sequence: UInt64
    public let timestamp: Double
    public init(pixels: Data, sequence: UInt64, timestamp: Double) {
        self.pixels = pixels; self.sequence = sequence; self.timestamp = timestamp
    }
}
public enum SessionPhase: String, Sendable { case idle, loading, running, paused, stopping, failed }
public struct GameRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String // SHA256 of imported content
    public var title: String
    public let importedAt: Date
    public init(id: String, title: String, importedAt: Date = Date()) {
        self.id = id; self.title = title; self.importedAt = importedAt
    }
}
