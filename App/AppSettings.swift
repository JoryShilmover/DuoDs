// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import Foundation

/// UserDefaults keys and defaults for the Settings screen. Views bind with @AppStorage(AppSettings.x);
/// the model reads the same keys when it boots a game.
enum AppSettings {
    static let controlScale = "controls.scale"
    static let controlOpacity = "controls.opacity"
    static let leftHanded = "controls.leftHanded"
    static let haptics = "settings.haptics"
    static let volume = "settings.volume"
    static let muted = "settings.muted"
    static let fastForwardSpeed = "settings.fastForwardSpeed"
    static let autoResume = "settings.autoResume"
    static let threadedRenderer = "settings.threadedRenderer"
    static let nickname = "settings.nickname"
    static let language = "settings.language"
    static let birthMonth = "settings.birthMonth"
    static let birthDay = "settings.birthDay"
    static let favoriteColor = "settings.favoriteColor"

    /// DS system languages the core accepts (melonDS DS option values).
    static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("ja", "Japanese"), ("fr", "French"), ("de", "German"), ("it", "Italian"), ("es", "Spanish")]
    /// DS profile colours, in firmware order.
    static let colors = ["Gray", "Brown", "Red", "Light Pink", "Orange", "Yellow", "Lime", "Light Green",
                         "Dark Green", "Turquoise", "Light Blue", "Blue", "Dark Blue", "Dark Purple", "Light Purple", "Dark Pink"]
    static let nicknameLimit = 10

    static var defaultLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return languages.contains { $0.code == code } ? code : "en"
    }

    static func register() {
        UserDefaults.standard.register(defaults: [
            controlScale: 1.0, controlOpacity: 1.0, leftHanded: false, haptics: true,
            volume: 1.0, muted: false, fastForwardSpeed: 2, autoResume: true, threadedRenderer: true,
            nickname: "", language: defaultLanguage, birthMonth: 0, birthDay: 0, favoriteColor: 0,
        ])
    }

    /// Core options for the next boot. Month/day 0 leaves the firmware's own value.
    static func coreOptions(_ defaults: UserDefaults = .standard) -> [String: String] {
        let month = defaults.integer(forKey: birthMonth), day = defaults.integer(forKey: birthDay)
        let validBirthday = (1...12).contains(month) && (1...31).contains(day)
        return [
            "melonds_threaded_renderer": defaults.bool(forKey: threadedRenderer) ? "enabled" : "disabled",
            "melonds_firmware_language": defaults.string(forKey: language) ?? "en",
            "melonds_firmware_favorite_color": String(max(0, min(15, defaults.integer(forKey: favoriteColor)))),
            "melonds_firmware_birth_month": validBirthday ? String(month) : "default",
            "melonds_firmware_birth_day": validBirthday ? String(day) : "default",
            // "Guess" asks the frontend (our nickname); without one keep the core's fixed default rather than
            // letting it guess from environment variables.
            "melonds_firmware_username": nickname(defaults).isEmpty ? "melonDS DS" : "guess_username",
        ]
    }

    static var autoResumeEnabled: Bool { UserDefaults.standard.bool(forKey: autoResume) }

    static func nickname(_ defaults: UserDefaults = .standard) -> String {
        String((defaults.string(forKey: nickname) ?? "").trimmingCharacters(in: .whitespaces).prefix(nicknameLimit))
    }
}
