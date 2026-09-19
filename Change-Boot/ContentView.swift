import AppKit
import SwiftUI

extension Notification.Name {
    /// Pozycja „Pomoc" w pasku menu otwiera okno i dopiero wtedy prosi je o arkusz —
    /// arkusza nie da się pokazać ze sceny `MenuBarExtra`, bo ta nie ma okna.
    static let changeBootShowHelp = Notification.Name("ChangeBootShowHelp")
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingSwitch: BootSystem?
    @State private var adding = false
    @State private var showingHelp = false
    @State private var showingOptions = false
    @Environment(\.accessibilityReduceMotion) private var ruchOgraniczony

    /// Kąt obrotu. `0` — lista, `180` — opcje. Wszystko inne to ruch między nimi.
    private var kat: Double { showingOptions ? 180 : 0 }

    /// Połowa czasu obrotu: w tym momencie jedna strona znika, a druga się pojawia.
    /// Gdyby przełączać widoczność bez opóźnienia, przez pół animacji widać byłoby
    /// lustrzane odbicie tej strony, która właśnie odjeżdża.
    private var polowa: Double { ruchOgraniczony ? 0 : 0.22 }
    private var czasObrotu: Double { ruchOgraniczony ? 0 : 0.45 }

    var body: some View {
        ZStack {
            przod
                .rotation3DEffect(.degrees(kat), axis: (x: 0, y: 1, z: 0),
                                  perspective: 0.35)
                .opacity(showingOptions ? 0 : 1)
                .animation(.linear(duration: 0.01).delay(polowa), value: showingOptions)
                .allowsHitTesting(!showingOptions)
                .accessibilityHidden(showingOptions)

            tyl
                // Tył jest **wstępnie obrócony o 180°**, inaczej po dojechaniu
                // animacji byłby odbiciem lustrzanym.
                .rotation3DEffect(.degrees(kat - 180), axis: (x: 0, y: 1, z: 0),
                                  perspective: 0.35)
                .opacity(showingOptions ? 1 : 0)
                .animation(.linear(duration: 0.01).delay(polowa), value: showingOptions)
                .allowsHitTesting(showingOptions)
                .accessibilityHidden(!showingOptions)
        }
        .animation(.easeInOut(duration: czasObrotu), value: showingOptions)
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
                    model.switchTo(system, cleanStart: model.configuration.cleanStartByDefault)
                }
                pendingSwitch = nil
            }
            Button("Cancel", role: .cancel) { pendingSwitch = nil }
        } message: {
            Text(model.configuration.cleanStartByDefault
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
        .sheet(isPresented: $showingHelp) { HelpView() }
        .onReceive(NotificationCenter.default.publisher(for: .changeBootShowHelp)) { _ in
            showingHelp = true
        }
    }

    /// Przód — lista systemów.
    private var przod: some View {
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
    }

    /// Tył — ustawienia. Ten sam nagłówek, żeby po obrocie było wiadomo, że to
    /// wciąż ten sam program, a nie nowe okno.
    private var tyl: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            SettingsView()
            Divider()
            HStack {
                Spacer()
                Button("Done") { showingOptions = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }

    /// Nagłówek jest wspólny dla obu stron — po obrocie ma być widać, że to wciąż
    /// ten sam program i wciąż ten sam system, z którego pracujesz.
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

    /// Stopka niesie **działania**, nie ustawienia.
    ///
    /// Do 0.1.17 dokładały się tutaj kolejne przełączniki, aż zrobiła się z tego
    /// zbieranina — [U] 2026-09-19 uciął to wprost. Ustawienia mają własne okno,
    /// a tutaj zostają: dodanie systemu, przejście do opcji, pomoc i numer wersji.
    private var footer: some View {
        HStack {
            Button {
                adding = true
            } label: {
                Label("Add system", systemImage: "plus")
            }
            Spacer()
            if model.busy { ProgressView().controlSize(.small) }
            Button {
                showingOptions = true
            } label: {
                Label("Options", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            Button {
                showingHelp = true
            } label: {
                Label("Help", systemImage: "questionmark.circle")
            }
            .help(Text("What each thing does"))
        }
        // Wersja przez `overlay`, nie między dwoma `Spacer()`: dwa odstępy
        // wyśrodkowałyby ją względem tego, co zostało po przyciskach, a te są
        // różnej szerokości. Tak stoi na środku stopki, nie na środku szpary.
        .overlay(alignment: .center) {
            Text(AppVersion.short)
                .font(.caption)
                .foregroundStyle(.tertiary)
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
