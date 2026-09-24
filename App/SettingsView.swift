// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var onDone: () -> Void
    @AppStorage(AppSettings.controlScale) private var controlScale = 1.0
    @AppStorage(AppSettings.controlOpacity) private var controlOpacity = 1.0
    @AppStorage(AppSettings.leftHanded) private var leftHanded = false
    @AppStorage(AppSettings.haptics) private var haptics = true
    @AppStorage(AppSettings.volume) private var volume = 1.0
    @AppStorage(AppSettings.muted) private var muted = false
    @AppStorage(AppSettings.fastForwardSpeed) private var fastForwardSpeed = 2
    @AppStorage(AppSettings.autoResume) private var autoResume = true
    @AppStorage(AppSettings.threadedRenderer) private var threadedRenderer = true
    @AppStorage(AppSettings.nickname) private var nickname = ""
    @AppStorage(AppSettings.language) private var language = AppSettings.defaultLanguage
    @AppStorage(AppSettings.birthMonth) private var birthMonth = 0
    @AppStorage(AppSettings.birthDay) private var birthDay = 0
    @AppStorage(AppSettings.favoriteColor) private var favoriteColor = 0

    private var nextStartNote: String {
        model.current == nil ? "Applies when you start a game." : "Applies the next time you start a game."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Controls") {
                    Picker("Size", selection: $controlScale) {
                        Text("Small").tag(0.75); Text("Medium").tag(0.88); Text("Large").tag(1.0)
                    }.pickerStyle(.segmented)
                    LabeledContent("Opacity") {
                        Slider(value: $controlOpacity, in: 0.2...1)
                    }
                    Toggle("Left-handed (D-pad on the right)", isOn: $leftHanded)
                    Toggle("Haptic feedback", isOn: $haptics)
                }
                Section("Sound") {
                    Toggle("Mute", isOn: $muted)
                    LabeledContent("Volume") {
                        Slider(value: $volume, in: 0...1)
                    }.disabled(muted)
                }
                Section {
                    Picker("Fast-forward speed", selection: $fastForwardSpeed) {
                        Text("2×").tag(2); Text("3×").tag(3); Text("4×").tag(4)
                    }
                    Toggle("Resume where you left off", isOn: $autoResume)
                } header: { Text("Play") } footer: {
                    Text("Fast-forward is the ▶▶ button. It skips most of the sound and can run slower than chosen in demanding scenes. Resuming keeps an automatic save state when you leave a game; it never replaces your in-game saves.")
                }
                Section {
                    TextField("Nickname", text: $nickname)
                        .textInputAutocapitalization(.words)
                        .onChange(of: nickname) { _, value in
                            if value.count > AppSettings.nicknameLimit { nickname = String(value.prefix(AppSettings.nicknameLimit)) }
                        }
                    Picker("Language", selection: $language) {
                        ForEach(AppSettings.languages, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    Picker("Birthday month", selection: $birthMonth) {
                        Text("Not set").tag(0)
                        ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) }
                    }
                    Picker("Birthday day", selection: $birthDay) {
                        Text("Not set").tag(0)
                        ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                    }.disabled(birthMonth == 0)
                    Picker("Favorite color", selection: $favoriteColor) {
                        ForEach(AppSettings.colors.indices, id: \.self) { Text(AppSettings.colors[$0]).tag($0) }
                    }
                } header: { Text("DS profile") } footer: {
                    Text("Some games greet you by name or use the console's language and birthday. \(nextStartNote)")
                }
                Section {
                    Toggle("Threaded 3D rendering", isOn: $threadedRenderer)
                } header: { Text("Performance") } footer: {
                    Text("Draws 3D scenes on a second processor core, which helps 3D-heavy games keep full speed. Turn it off if a game shows glitches. \(nextStartNote)")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done", action: onDone) }
            .onChange(of: volume) { _, _ in model.applyAudioSettings() }
            .onChange(of: muted) { _, _ in model.applyAudioSettings() }
        }
    }
}
