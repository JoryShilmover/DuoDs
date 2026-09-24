// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import Foundation

/// The icon and title a DS cartridge carries for the system menu (the "banner", pointed to by header 0x68).
public struct NDSBanner: Equatable, Sendable {
    public static let iconSide = 32
    /// 32×32 RGBA8, row-major; palette index 0 is fully transparent (all zero), others opaque.
    public let iconRGBA: Data
    /// Title lines as the cartridge stores them, e.g. ["Game Name", "Publisher"] or ["Game", "Subtitle", "Publisher"].
    public let titleLines: [String]

    /// Everything before the publisher line.
    public var title: String { titleLines.count > 1 ? titleLines.dropLast().joined(separator: " ") : titleLines.first ?? "" }
    public var publisher: String? { titleLines.count > 1 ? titleLines.last : nil }

    static let length = 0x840
    private static let englishTitle = 0x340, japaneseTitle = 0x240

    /// Parses the banner from the start of a ROM file, reading only the header and banner.
    public static func read(from url: URL) -> NDSBanner? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 0x200), header.count == 0x200 else { return nil }
        let offset = Int(header.littleEndianUInt32(at: 0x68))
        guard offset >= 0x200, (try? handle.seek(toOffset: UInt64(offset))) != nil,
              let banner = try? handle.read(upToCount: length) else { return nil }
        return parse(banner)
    }

    public static func parse(_ banner: Data) -> NDSBanner? {
        guard banner.count >= length else { return nil }
        let bytes = [UInt8](banner.prefix(length))
        let version = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        guard [1, 2, 3, 0x103].contains(version) else { return nil }

        var palette = [(UInt8, UInt8, UInt8)]()
        for i in 0..<16 {
            let c = UInt16(bytes[0x220 + i * 2]) | UInt16(bytes[0x221 + i * 2]) << 8 // BGR555
            func expand(_ v: UInt16) -> UInt8 { UInt8((v << 3) | (v >> 2)) }
            palette.append((expand(c & 0x1F), expand((c >> 5) & 0x1F), expand((c >> 10) & 0x1F)))
        }
        // 4 bpp, 4×4 tiles of 8×8 pixels, low nibble is the left pixel.
        var rgba = [UInt8](repeating: 0, count: iconSide * iconSide * 4)
        for tile in 0..<16 {
            for row in 0..<8 {
                for pair in 0..<4 {
                    let byte = bytes[0x20 + tile * 32 + row * 4 + pair]
                    for (half, index) in [Int(byte & 0x0F), Int(byte >> 4)].enumerated() {
                        let x = (tile % 4) * 8 + pair * 2 + half, y = (tile / 4) * 8 + row
                        let p = (y * iconSide + x) * 4
                        guard index != 0 else { continue } // transparent: all zero, valid as premultiplied too
                        let color = palette[index]
                        rgba[p] = color.0; rgba[p + 1] = color.1; rgba[p + 2] = color.2; rgba[p + 3] = 255
                    }
                }
            }
        }
        let lines = title(bytes, at: englishTitle) ?? title(bytes, at: japaneseTitle) ?? []
        return NDSBanner(iconRGBA: Data(rgba), titleLines: lines)
    }

    /// UTF-16LE, 128 code units, NUL-terminated, lines separated by "\n".
    private static func title(_ bytes: [UInt8], at offset: Int) -> [String]? {
        var units: [UInt16] = []
        for i in 0..<128 {
            let unit = UInt16(bytes[offset + i * 2]) | UInt16(bytes[offset + i * 2 + 1]) << 8
            if unit == 0 { break }
            units.append(unit)
        }
        let text = String(decoding: units, as: UTF16.self)
        let lines = text.split(separator: "\n").map {
            String(String.UnicodeScalarView($0.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
                .trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines
    }
}

extension Data {
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[self.startIndex + offset + $1]) << (8 * $1) }
    }
}
