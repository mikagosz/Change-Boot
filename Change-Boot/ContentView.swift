import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingSwitch: BootSystem?
    @State private var adding = false

    var body: some View {
        @Bindable var configuration = model.configuration

        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if model.rows.isEmpty {
                ContentUnavailableView(
                    "No systems configured",
                    systemImage: "internaldrive",
                    description: Text("Add a startup system to switch to."))
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.rows) { row in
                        SystemRowView(row: row) { pendingSwitch = $0 }
                    }
                    .onMove { model.configuration.move(from: $0, to: $1) }
                }
                .listStyle(.inset)
            }

            Divider()
            footer
        }
        .frame(minWidth: 440, minHeight: 380)
        .task { model.refresh() }
        .confirmationDialog(
            pendingSwitch.map { Text("Restart from “\($0.name)”?") } ?? Text(""),
            isPresented: Binding(get: { pendingSwitch != nil },
                                 set: { if !$0 { pendingSwitch = nil } }),
            titleVisibility: .visible)
        {
            Button("Restart") {
                if let system = pendingSwitch {
                    model.switchTo(system, cleanStart: configuration.cleanStartByDefault)
                }
                pendingSwitch = nil
            }
            Button("Cancel", role: .cancel) { pendingSwitch = nil }
        } message: {
            Text(configuration.cleanStartByDefault
                 ? "Apps and windows from this session will not come back."
                 : "macOS will reopen the apps and windows you have open now.")
        }
        .alert("Change-Boot", isPresented: Binding(
            get: { model.failure != nil },
            set: { if !$0 { model.failure = nil } })) {
            Button("OK", role: .cancel) { model.failure = nil }
        } message: {
            Text(model.failure ?? "")
        }
        .sheet(isPresented: $adding) { AddSystemSheet() }
    }

    /// Numer wersji z bundla — jedno źródło, to samo co w Informacjach o programie.
    private var wersjaProgramu: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Running from “\(model.current?.name ?? "?")”")
                    .font(.headline)
                if let current = model.current {
                    Text("macOS \(current.productVersion) · \(current.deviceIdentifier)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
    }

    private var footer: some View {
        @Bindable var configuration = model.configuration
        return VStack(alignment: .leading, spacing: 8) {
            Toggle("Clean start — do not reopen apps and windows",
                   isOn: $configuration.cleanStartByDefault)
            Toggle("Show icon in the menu bar",
                   isOn: $configuration.showsMenuBarIcon)
            HStack {
                Button {
                    adding = true
                } label: {
                    Label("Add system", systemImage: "plus")
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Text(wersjaProgramu)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
    }
}

struct SystemRowView: View {
    @Environment(AppModel.self) private var model
    let row: SystemRow
    let onSwitch: (BootSystem) -> Void

    @State private var pickingColour = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                pickingColour = true
            } label: {
                Image(systemName: icon)
                    // Odpięty dysk zachowuje swój kolor, tylko przygaszony — inaczej
                    // wszystkie nieobecne wyglądałyby jednakowo.
                    .foregroundStyle(row.entry.color.color.opacity(row.isAvailable ? 1 : 0.35))
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .help(Text("Change colour"))
            .accessibilityLabel(Text("Colour: \(Text(row.entry.color.label))"))
            .popover(isPresented: $pickingColour, arrowEdge: .bottom) {
                ColorPickerPopover(current: row.entry.color) { picked in
                    model.configuration.setColor(picked, for: row.entry)
                    pickingColour = false
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .foregroundStyle(row.isAvailable ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isCurrent(row.system) {
                Text("Current")
                    .font(.caption)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            } else if let system = row.system {
                if !system.isInternal {
                    Button {
                        model.eject(system)
                    } label: {
                        Label("Eject", systemImage: "eject.fill")
                    }
                    .help(Text("Unmount the whole disk so it can be unplugged safely"))
                    .disabled(model.busy)
                }
                Button("Switch") { onSwitch(system) }
                    .disabled(model.busy)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Menu("Colour") {
                ForEach(SystemColor.allCases) { option in
                    Button {
                        model.configuration.setColor(option, for: row.entry)
                    } label: {
                        Label { Text(option.label) } icon: { ColorDot(color: option) }
                    }
                }
            }
            Divider()
            Button("Remove from list", role: .destructive) {
                model.configuration.remove(row.entry)
            }
            .disabled(model.isCurrent(row.system))
        }
    }

    private var icon: String {
        guard let system = row.system else { return "questionmark.circle" }
        return system.isInternal ? "internaldrive.fill" : "externaldrive.fill"
    }

    private var subtitle: String {
        guard let system = row.system else {
            return String(localized: "Not connected")
        }
        return "macOS \(system.productVersion) · \(system.deviceIdentifier)"
    }
}

/// Dokładanie kolejnego systemu do listy — także po wymianie dysku.
struct AddSystemSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a startup system").font(.headline)

            if model.unconfigured.isEmpty {
                Text("Every macOS installation found right now is already on the list. Connect another disk and it will show up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.unconfigured) { system in
                    HStack {
                        Image(systemName: system.isInternal ? "internaldrive" : "externaldrive")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(system.name)
                            Text("macOS \(system.productVersion) · \(system.deviceIdentifier)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add") { model.configuration.add(system) }
                    }
                }
            }

            HStack {
                Button("Rescan") { model.refresh() }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
