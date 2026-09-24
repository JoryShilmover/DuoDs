import SwiftUI
import UniformTypeIdentifiers

@main struct DuoDSApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}

struct RootView: View {
    @StateObject private var model = AppModel.shared
    @ObservedObject private var session = EmulationSession.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var sceneID = UUID()
    @State private var importing = false
    @State private var swapped = false
    @State private var preference = ScreenLayoutPreference.automatic

    var body: some View {
        NavigationStack {
            Group {
                if model.owner != nil && model.owner != sceneID {
                    ContentUnavailableView("Session in another window", systemImage: "rectangle.on.rectangle", description: Text("Duo DS runs one emulation session. Return to its original window."))
                } else if model.current != nil {
                    VStack(spacing: 0) {
                        PlaySessionView(frame: session.frame, preference: preference, swapScreens: swapped,
                                        onInput: { session.setInput($0) },
                                        onPause: { Task { await model.pauseAndSave(reason: "explicit-pause") } },
                                        onLidToggle: { session.toggleLid() },
                                        onGeometry: { model.recordGeometry($0, $1) },
                                        inputEpoch: session.inputEpoch)
                        // Overlay, not a stacked row: pausing must not resize the play area and move the DS screens.
                        .overlay {
                            if session.phase == .paused {
                                Button("Resume") { Task { await model.resume() } }.buttonStyle(.borderedProminent).controlSize(.large)
                            }
                        }
                        HStack {
                            Text(session.phase.rawValue.capitalized)
                            Spacer()
                            Text("\(session.stats.frames) frames · \(session.stats.fps, specifier: "%.2f") Hz core")
                        }.font(.caption.monospacedDigit()).padding(8)
                        if let error = session.errorMessage { Text(error).foregroundStyle(.red).padding() }
                    }
                } else {
                    List {
                        Section {
                            Text("Import a lawfully supplied Nintendo DS file to play. No games or system firmware are downloaded.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Import .nds file", systemImage: "square.and.arrow.down") { importing = true }
                        }
                        Section("Library") {
                            ForEach(model.games) { game in
                                Button { Task { await model.launch(game) } } label: {
                                    Label(game.title, systemImage: "gamecontroller")
                                }.swipeActions { Button("Delete", role: .destructive) { model.delete(game) } }
                            }
                        }
                        Section("Prototype") {
                            Text("Interpreter · native software rendering · Metal presentation")
                            Text("Microphone input is not yet available. Homebrew manual save states are unsupported by the core.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(model.current?.title ?? "Duo DS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.current != nil {
                    ToolbarItem(placement: .topBarLeading) { Button("Library") { Task { await model.close() } } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Swap screens") { session.releaseInputs(); swapped.toggle() }
                            Picker("Layout", selection: $preference) {
                                Text("Automatic").tag(ScreenLayoutPreference.automatic)
                                Text("Stacked").tag(ScreenLayoutPreference.stacked)
                                Text("Side by side").tag(ScreenLayoutPreference.sideBySide)
                            }
                            Button("Pause & save progress") { Task { await model.pauseAndSave(reason: "explicit-pause") } }
                            Button("Save manual state") { Task { await model.state(save: true) } }
                            Button("Restore manual state") { Task { await model.state(save: false) } }
                            Button("Toggle emulated DS lid") { session.toggleLid() }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .overlay { if model.busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "nds") ?? .data]) { result in
                switch result { case .success(let url): Task { await model.importROM(url) }; case .failure(let error): model.message = error.localizedDescription }
            }
            .alert("Duo DS", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button("OK") { model.message = nil }
            } message: { Text(model.message ?? "") }
        }
        .task { model.claim(sceneID); await model.active(scenePhase == .active, scene: sceneID) }
        .onChange(of: scenePhase) { _, phase in Task { await model.active(phase == .active, scene: sceneID) } }
    }
}
