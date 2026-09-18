import AppKit
import SwiftUI

/// Kreator pierwszego uruchomienia.
///
/// Bieżący system rozpoznaje się sam i wchodzi na listę bez pytania — to jedyny,
/// co do którego nie ma wątpliwości. Resztę wskazuje użytkownik i może wrócić po
/// kolejne w każdej chwili, także po wymianie dysku.
struct SetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Change-Boot").font(.title2).bold()
                Text("Pick the systems you want to switch between. You can add more later.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let current = model.current {
                GroupBox {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(current.name) — this system")
                            Text("macOS \(current.productVersion) · \(current.deviceIdentifier)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }

            Text("Other systems found").font(.headline)

            if model.unconfigured.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No other macOS installation is connected right now.")
                        .foregroundStyle(.secondary)
                    Text("Connect the disk you want to boot from and press Rescan.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                List(model.unconfigured) { system in
                    HStack(spacing: 10) {
                        Image(systemName: system.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(system.name)
                            Text("macOS \(system.productVersion) · \(system.deviceIdentifier)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        // Dysk zewnętrzny można odpiąć już tutaj, bez przechodzenia dalej.
                        if !system.isInternal {
                            Button {
                                model.eject(system)
                            } label: {
                                Label("Eject", systemImage: "eject.fill")
                            }
                            .help(Text("Unmount the whole disk so it can be unplugged safely"))
                            .disabled(model.busy)
                        }
                        Button("Add") { model.configuration.add(system) }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 100)
            }

            if !model.configuration.entries.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("On the list").font(.callout).foregroundStyle(.secondary)
                    // Kolory przydzielają się same, po jednym z palety — tutaj widać,
                    // który system dostał który.
                    ForEach(model.configuration.entries) { entry in
                        HStack(spacing: 7) {
                            ColorDot(color: entry.color)
                            Text(entry.lastKnownName).font(.callout)
                            Spacer()
                            if !model.isCurrent(model.detected.first { $0.volumeUUID == entry.volumeUUID }) {
                                Button("Remove") { model.configuration.remove(entry) }
                                    .buttonStyle(.link)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Rescan") { model.refresh() }
                Spacer()
                // Bieżący system trafia na listę już przy skanowaniu, więc tutaj
                // zostaje samo domknięcie kreatora.
                Button("Done") { model.configuration.setupCompleted = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.configuration.entries.isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 460, minHeight: 420)
        .task { model.refresh() }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let current = model.current {
            Text("Running from \(current.name)")
            Divider()
        }

        ForEach(model.rows) { row in
            if let system = row.system, !model.isCurrent(system) {
                Button("Restart from \(system.name)") {
                    model.switchTo(system, cleanStart: model.configuration.cleanStartByDefault)
                }
            }
        }

        Divider()
        // Po zamknięciu okna scena przestaje istnieć, więc szukanie go w
        // NSApp.windows nic nie da — okno trzeba otworzyć na nowo po identyfikatorze.
        Button("Open Change-Boot") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button("Quit") { NSApp.terminate(nil) }
    }
}
