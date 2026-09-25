// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import DualPaneCore
import SwiftUI
import UniformTypeIdentifiers

@main struct DuoDSApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}

struct RootView: View {
    @StateObject private var model = AppModel.shared
    // Not observed here: the session publishes every frame, and re-evaluating this body at 60 Hz rebuilds
    // the toolbar Menu while it is open, which cancels taps on its items. PlayArea observes it instead.
    private let session = EmulationSession.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var sceneID = UUID()
    @State private var swapped = false
    @State private var preference = ArrangementPreference.automatic
    @State private var showingSettings = false
    @State private var showingStates = false
    /// One file importer serves every import; the mode decides what it accepts and where the file goes.
    private enum ImportMode { case rom, save(GameRecord), backup }
    @State private var importMode: ImportMode?
    /// Files made for export (a `.sav` or a backup ZIP), moved to a place the user picks.
    @State private var exportFile: URL?

    var body: some View {
        NavigationStack {
            Group {
                if model.owner != nil && model.owner != sceneID {
                    ContentUnavailableView {
                        Label("Session in another window", systemImage: "rectangle.on.rectangle")
                    } description: {
                        Text("Duo DS runs one emulation session at a time.")
                    } actions: {
                        Button("Move game here") { Task { await model.takeOver(sceneID) } }.buttonStyle(.borderedProminent)
                    }
                } else if model.current != nil {
                    PlayArea(session: session, model: model, preference: preference, swapped: swapped)
                } else {
                    library
                }
            }
            .navigationTitle(model.current.map(model.displayTitle) ?? "Duo DS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.current != nil {
                    ToolbarItem(placement: .topBarLeading) { Button("Library") { Task { await model.close() } } }
                    ToolbarItem(placement: .topBarTrailing) { gameMenu }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                    }
                    ToolbarItem(placement: .topBarTrailing) { libraryMenu }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView(model: model) { showingSettings = false } }
            .sheet(isPresented: $showingStates) {
                StatesView(model: model) { showingStates = false }.presentationDetents([.medium, .large])
            }
            .overlay { if model.busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .fileImporter(isPresented: Binding(get: { importMode != nil }, set: { if !$0 { importMode = nil } }),
                          allowedContentTypes: importTypes) { result in
                let mode = importMode
                importMode = nil
                switch result {
                case .success(let url):
                    Task {
                        switch mode {
                        case .rom: await model.importROM(url)
                        case .save(let game): await model.importSave(from: url, for: game)
                        case .backup: await model.restoreBackup(from: url)
                        case nil: break
                        }
                    }
                case .failure(let error): model.message = error.localizedDescription
                }
            }
            .fileMover(isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }), file: exportFile) { result in
                if case .failure(let error) = result { model.message = "Export failed: \(error.localizedDescription)" }
                exportFile = nil
            }
            .alert("Duo DS", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button("OK") { model.message = nil }
            } message: { Text(model.message ?? "") }
        }
        .task { model.claim(sceneID); await model.active(scenePhase == .active, scene: sceneID) }
        .onDisappear { Task { await model.release(sceneID) } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() } // picks up games added in Files while away
            Task { await model.active(phase == .active, scene: sceneID) }
        }
    }

    private var importTypes: [UTType] {
        switch importMode {
        case .rom: return [UTType(filenameExtension: "nds") ?? .data]
        case .backup: return [.zip]
        case .save, nil: return [.data]
        }
    }

    // MARK: Library

    @ViewBuilder private var library: some View {
        if model.games.isEmpty && model.inbox.isEmpty {
            ContentUnavailableView {
                Label("No games yet", systemImage: "gamecontroller")
            } description: {
                Text("Duo DS plays Nintendo DS games you already own. It doesn't include or download any games.\n\nChoose a .nds file from Files, or copy .nds files to Files → On My iPhone → Duo DS and they'll appear here.")
            } actions: {
                Button("Choose a Game File") { importMode = .rom }.buttonStyle(.borderedProminent)
            }
        } else {
            List {
                if !model.inbox.isEmpty {
                    Section {
                        ForEach(model.inbox, id: \.self) { url in
                            HStack {
                                Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc")
                                Spacer()
                                Button("Add") { Task { await model.importFromInbox(url) } }.buttonStyle(.bordered)
                            }
                        }
                    } header: { Text("In your Duo DS folder") } footer: {
                        Text("Adding a game moves it from the folder into your library.")
                    }
                }
                Section("Library") {
                    ForEach(model.games) { game in
                        Button { Task { await model.launch(game) } } label: { gameRow(game) }
                            .buttonStyle(.plain)
                            .swipeActions { Button("Delete", role: .destructive) { model.delete(game) } }
                            .contextMenu {
                                Button("Export Save…", systemImage: "square.and.arrow.up") {
                                    Task { exportFile = await model.exportSave(game) }
                                }
                                Button("Import Save…", systemImage: "square.and.arrow.down") { importMode = .save(game) }
                                if model.resumable.contains(game.id) {
                                    Button("Start from In-Game Save", systemImage: "arrow.counterclockwise") {
                                        Task { await model.launchFresh(game) }
                                    }
                                }
                                Button("Delete Game", systemImage: "trash", role: .destructive) { model.delete(game) }
                            }
                    }
                }
                Section {
                    Button("Add a Game from Files", systemImage: "plus") { importMode = .rom }
                } footer: {
                    Text("Touch and hold a game to export or import its save. Interpreter · native software rendering · Metal presentation.")
                }
            }
        }
    }

    private func gameRow(_ game: GameRecord) -> some View {
        HStack(spacing: 12) {
            GameIcon(banner: model.banners[game.id])
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayTitle(game)).font(.body).foregroundStyle(.primary).lineLimit(2)
                if let publisher = model.banners[game.id]?.publisher {
                    Text(publisher).font(.caption).foregroundStyle(.secondary)
                }
                if model.resumable.contains(game.id) {
                    Label("Resumes where you left off", systemImage: "play.circle").font(.caption2).foregroundStyle(.tint)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var libraryMenu: some View {
        Menu {
            Button("Add a Game from Files", systemImage: "plus") { importMode = .rom }
            Divider()
            Button("Back Up All Saves…", systemImage: "externaldrive") { Task { exportFile = await model.exportBackup() } }
            Button("Restore from Backup…", systemImage: "clock.arrow.circlepath") { importMode = .backup }
        } label: { Image(systemName: "ellipsis.circle") }
    }

    // MARK: In-game menu

    private var gameMenu: some View {
        Menu {
            Button("Save States…", systemImage: "square.stack") { Task { await model.pauseAndSave(reason: "explicit-pause"); showingStates = true } }
            Button(model.fastForward ? "Stop Fast-Forward" : "Fast-Forward", systemImage: "forward") { model.toggleFastForward() }
            Button("Swap screens") { session.releaseInputs(); swapped.toggle() }
            Picker("Layout", selection: $preference) {
                Text("Automatic").tag(ArrangementPreference.automatic)
                Text("Stacked").tag(ArrangementPreference.stacked)
                Text("Side by side").tag(ArrangementPreference.sideBySide)
            }
            Button("Pause & save progress") { Task { await model.pauseAndSave(reason: "explicit-pause") } }
            Button("Toggle emulated DS lid") { session.toggleLid() }
            Button("Settings…", systemImage: "gearshape") { showingSettings = true }
        } label: { Image(systemName: "ellipsis.circle") }
    }
}

/// The cartridge's 32×32 icon, drawn with hard pixels.
struct GameIcon: View {
    let banner: NDSBanner?
    var body: some View {
        Group {
            if let banner, let image = Self.image(banner) {
                Image(decorative: image, scale: 1).resizable().interpolation(.none)
            } else {
                Image(systemName: "gamecontroller").font(.title2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 48)
    }
    static func image(_ banner: NDSBanner) -> CGImage? {
        guard banner.iconRGBA.count == NDSBanner.iconSide * NDSBanner.iconSide * 4,
              let provider = CGDataProvider(data: banner.iconRGBA as CFData) else { return nil }
        return CGImage(width: NDSBanner.iconSide, height: NDSBanner.iconSide, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: NDSBanner.iconSide * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// The only view that observes the per-frame session updates.
struct PlayArea: View {
    @ObservedObject var session: EmulationSession
    @ObservedObject var model: AppModel
    let preference: ArrangementPreference
    let swapped: Bool
    @AppStorage(AppSettings.controlScale) private var controlScale = 1.0
    @AppStorage(AppSettings.controlOpacity) private var controlOpacity = 1.0
    @AppStorage(AppSettings.leftHanded) private var leftHanded = false
    @AppStorage(AppSettings.haptics) private var haptics = true

    var body: some View {
        VStack(spacing: 0) {
            PlaySessionView(frame: session.frame, preference: preference, swapScreens: swapped,
                            onInput: { session.setInput($0) },
                            onPause: { Task { await model.pauseAndSave(reason: "explicit-pause") } },
                            onLidToggle: { session.toggleLid() },
                            onGeometry: { model.recordGeometry($0, $1) },
                            inputEpoch: session.inputEpoch,
                            onStylusSample: { model.recordStylus($0, lowerScreen: $1, uptime: $2) },
                            onMicrophone: { held in Task { await model.microphone(held: held) } })
                .controlSettings(scale: controlScale, opacity: controlOpacity, leftHanded: leftHanded, haptics: haptics)
                .fastForward(active: model.fastForward) { model.toggleFastForward() }
            // Overlay, not a stacked row: pausing must not resize the play area and move the DS screens.
            .overlay {
                if session.phase == .paused {
                    Button("Resume") { Task { await model.resume() } }.buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
            HStack {
                Text(session.phase.rawValue.capitalized)
                if model.fastForward { Text("▶▶ Fast-forward").foregroundStyle(.tint) }
                Spacer()
                Text("\(session.stats.frames) frames · \(session.stats.fps, specifier: "%.2f") Hz core")
            }.font(.caption.monospacedDigit()).padding(8)
            if let error = session.errorMessage { Text(error).foregroundStyle(.red).padding() }
        }
    }
}
