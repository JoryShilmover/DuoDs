// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import SwiftUI

/// Manual save-state slots for the running game: thumbnail, time, Save and Load.
struct StatesView: View {
    @ObservedObject var model: AppModel
    var onDone: () -> Void
    @State private var confirmOverwrite: Int?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(1...StateSlot.manualCount, id: \.self) { slot in row(slot) }
                } footer: {
                    Text("Loading a state also returns in-game saves to that moment. States work only with this version of Duo DS; your in-game saves always carry over.")
                }
            }
            .navigationTitle("Save States")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done", action: onDone) }
            .confirmationDialog("Replace the state in this slot?", isPresented: Binding(get: { confirmOverwrite != nil }, set: { if !$0 { confirmOverwrite = nil } }),
                                titleVisibility: .visible, presenting: confirmOverwrite) { slot in
                Button("Replace Slot \(slot)", role: .destructive) { Task { await model.saveState(slot: slot) } }
            }
        }
    }

    @ViewBuilder private func row(_ slot: Int) -> some View {
        let _ = model.statesRevision // re-read slot info after saves and deletes
        let info = model.stateInfo(slot: slot)
        HStack(spacing: 12) {
            Group {
                if let data = info?.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().interpolation(.none)
                } else {
                    Rectangle().fill(.quaternary).overlay(Text("Empty").font(.caption2).foregroundStyle(.secondary))
                }
            }
            .frame(width: 48, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text("Slot \(slot)").font(.headline)
                Text(info.map { $0.date.formatted(date: .abbreviated, time: .shortened) } ?? "No state saved")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Save") {
                if info != nil { confirmOverwrite = slot } else { Task { await model.saveState(slot: slot) } }
            }.buttonStyle(.bordered)
            Button("Load") {
                Task { if await model.loadState(slot: slot) { onDone() } }
            }.buttonStyle(.borderedProminent).disabled(info == nil)
        }
        .swipeActions { if info != nil { Button("Delete", role: .destructive) { model.deleteState(slot: slot) } } }
    }
}
