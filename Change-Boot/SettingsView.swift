import AppKit
import SwiftUI
import ServiceManagement

/// Ekran ustawień — **jedyne** miejsce, w którym stoją opcje programu.
///
/// Powstał na polecenie [U] 2026-09-19: *„wstaw w oknie głównym przycisk «opcje»,
/// po kliknięciu przechodzimy na okno ustawień i tam niech będą wszystkie opcje
/// i ustawienia"*. Do 0.1.17 ustawienia dokładały się pojedynczo do stopki okna
/// głównego i po trzecim przełączniku zrobiła się z tego zbieranina.
///
/// Wchodzi **w to samo okno**, nie w nowe — doprecyzowanie [U] chwilę później:
/// *„nie kolejne okno tylko opcje mają się w tym samym otworzyć"*. Stąd brak
/// własnej ramki: rozmiar narzuca okno główne.
///
/// Zasada na przyszłość: **nowe ustawienie idzie tutaj**, nie do stopki listy.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var language = AppLanguage.current
    /// Język z chwili otwarcia okna — patrz `LanguageMenu`: wybór zapisuje się od
    /// razu, więc bez tego przycisk restartu byłby wyłączony zawsze.
    @State private var languageAtOpen = AppLanguage.current
    @State private var helperStatus = HelperClient.statusDescription
    @State private var helperFailure: String?
    @State private var busy = false
    @State private var historia: EventLog.Odczyt = .pusty
    @State private var pytanieOOdinstalowanie = false
    @State private var wynikOdinstalowania: String?
    @State private var stanPolecenia = CommandLineInstall.opisStanu
    @State private var poleceniZainstalowane = CommandLineInstall.stan == .zainstalowane

    private var formater: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }

    private func ikona(_ skutek: EventLog.Skutek) -> String {
        switch skutek {
        case .udane:     return "checkmark.circle.fill"
        case .nieudane:  return "xmark.circle.fill"
        case .anulowane: return "minus.circle.fill"
        case .oczekuje:  return "clock.fill"
        // Skutek z nowszej wersji programu. Znak zapytania, nie milczenie —
        // wpis ma być widoczny nawet wtedy, gdy nie wiadomo, co znaczy.
        case .inny:      return "questionmark.circle.fill"
        }
    }

    private func kolor(_ skutek: EventLog.Skutek) -> Color {
        switch skutek {
        case .udane:     return .green
        case .nieudane:  return .red
        case .anulowane: return .secondary
        case .oczekuje:  return .orange
        case .inny:      return .secondary
        }
    }

    /// Zdanie po ludzku, nie surowe pola zapisu.
    ///
    /// 🔴 Składane z **kluczy katalogu**, nie z polskich literałów. Do 0.2.6 stały
    /// tu zdania wpisane wprost po polsku, a `Text(String)` katalogu nie dotyka —
    /// więc sekcja Historia mówiła po polsku także przy programie ustawionym na
    /// angielski, mimo że Pomoc obiecywała dwa języki (P1-05 z audytu 2026-09-19).
    ///
    /// Zdanie składa się z kawałków, a nie z jednego klucza na każdą kombinację:
    /// czynność razy źródło razy czysty start to dwanaście kluczy zamiast dziewięciu,
    /// a przy każdej nowej czynności rosłoby to mnożąc się dalej.
    private func opis(_ wpis: EventLog.Entry) -> String {
        let zrodlo = wpis.zrodlo == .wierszPolecen
            ? String(localized: " (command line)")
            : ""
        let cel = wpis.naSystem ?? "?"
        switch wpis.czynnosc {
        case .przelaczenie:
            let czysty = (wpis.czystyStart ?? false) ? String(localized: ", clean start") : ""
            return String(localized: "Switch to “\(cel)”") + czysty + zrodlo
        case .wysuniecie:
            return String(localized: "Eject “\(cel)”") + zrodlo
        case .instalacjaPomocnika:
            return String(localized: "Helper installed") + zrodlo
        case .usunieciePomocnika:
            return String(localized: "Helper removed") + zrodlo
        case .instalacjaPolecenia:
            return String(localized: "Terminal command installed") + zrodlo
        case .usunieciePolecenia:
            return String(localized: "Terminal command removed") + zrodlo
        case .uzbrojenieNaPowrot:
            return String(localized: "Set to open when you come back to this system") + zrodlo
        case .inna(let surowa):
            // Czynność zapisana przez nowszą wersję. Pokazujemy surową nazwę
            // zamiast chować wpis — patrz `TekstoweWyliczenie`.
            return String(localized: "Unknown event: \(surowa)") + zrodlo
        }
    }

    /// Zdanie tłumaczące szare przełączniki. Z nazwą organizacji, gdy profil ją
    /// podał — „twoja organizacja" bez nazwy brzmi jak wymówka programu.
    private func zdanieOProfilu() -> String {
        if let kto = Polityka.organizacja {
            return String(localized: "Some settings are managed by \(kto) and cannot be changed here.")
        }
        return String(localized: "Some settings are managed by a configuration profile and cannot be changed here.")
    }

    var body: some View {
        @Bindable var configuration = model.configuration

        Form {
            // 🔴 Zdanie o profilu stoi NA GÓRZE, przed pierwszym zablokowanym
            // przełącznikiem, a nie pod nim. Człowiek, który widzi szary
            // przełącznik i nie wie dlaczego, zgłasza to jako usterkę programu.
            if Polityka.czyZarzadzany {
                Section {
                    Label(zdanieOProfilu(), systemImage: "building.2")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Switching") {
                Toggle("Clean start — do not reopen apps and windows",
                       isOn: $configuration.cleanStartByDefault)
                    .disabled(configuration.zablokowane(Configuration.Key.cleanStart))
            }

            Section("Menu bar icon") {
                Toggle("Show icon in the menu bar",
                       isOn: $configuration.showsMenuBarIcon)
                    .disabled(configuration.zablokowane(Configuration.Key.menuBar))
                Toggle("Menu bar icon without colours",
                       isOn: $configuration.monochromeMenuBarIcon)
                    .disabled(!configuration.showsMenuBarIcon
                              || configuration.zablokowane(Configuration.Key.monoMenuBar))
                Toggle("Hide the Dock icon when the window is closed",
                       isOn: $configuration.hidesDockIcon)
                    .disabled(!configuration.showsMenuBarIcon
                              || configuration.zablokowane(Configuration.Key.hideDock))
                    .onChange(of: configuration.hidesDockIcon) { _, _ in
                        AppDelegate.aktualizujObecnoscWDocku()
                    }

                // 🔴 Bez tego zdania ustawienie wygląda na zepsute. Program zdejmuje
                // się z Docka poprawnie, a macOS wstawia go z powrotem — jako
                // „ostatnio używany". To druga, niezależna ścieżka do tego samego
                // miejsca i programowi nie wolno jej dotykać, bo to ustawienie Docka,
                // nie Change-Boota. Zgłoszone przez [U] 2026-09-19 ze zrzutem panelu
                // „Biurko i Dock".
                if configuration.hidesDockIcon && configuration.showsMenuBarIcon {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("macOS puts recently used apps back in the Dock on its own. For the icon to really stay away, turn off “Show suggested and recent apps in Dock” in System Settings.",
                              systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Desktop & Dock settings") {
                            AppDelegate.otworzUstawieniaDocka()
                        }
                    }
                }
            }

            Section("Opening Change-Boot") {
                Toggle("Open Change-Boot when I come back to this system",
                       isOn: $configuration.launchAfterSwitch)
                    .disabled(configuration.zablokowane(Configuration.Key.launchAfterSwitch))
                Text("Switching from here sets a one-off login item on this system. Come back to it and Change-Boot is already open, ready to eject the disk you just arrived from. The item removes itself at that start.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Open Change-Boot at every login", isOn: $configuration.launchAtLogin)
                    .disabled(configuration.zablokowane(Configuration.Key.launchAtLogin))
                    .onChange(of: configuration.launchAtLogin) { _, wlaczony in
                        do {
                            try LoginItem.ustaw(wlaczony)
                        } catch {
                            helperFailure = error.localizedDescription
                            configuration.launchAtLogin = LoginItem.wlaczony
                        }
                    }

                if configuration.launchAtLogin && LoginItem.czekaNaZgode {
                    HStack {
                        Label("Waiting for approval in System Settings → General → Login Items.",
                              systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Open System Settings") { HelperClient.openLoginItemsSettings() }
                    }
                }
            }

            Section("Language") {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .onChange(of: language) { _, new in AppLanguage.apply(new) }

                if language != languageAtOpen {
                    HStack {
                        Text("Change-Boot has to restart to load the other language.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Change-Boot") { AppLanguage.relaunch() }
                    }
                }
            }

            Section("Password") {
                Text("Changing the startup disk needs administrator rights. Install the helper once and Change-Boot stops asking for your password on every switch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: HelperClient.isReady ? "lock.open" : "lock")
                        .foregroundStyle(HelperClient.isReady ? .green : .secondary)
                    Text(helperStatus)
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    if HelperClient.status == .requiresApproval {
                        Button("Open System Settings") { HelperClient.openLoginItemsSettings() }
                    }
                    if HelperClient.isReady {
                        Button("Remove helper") { run(HelperClient.uninstall, czynnosc: .usunieciePomocnika) }
                    } else {
                        Button("Install helper") { zainstalujPomocnika() }
                    }
                }
                .disabled(busy)

                if HelperClient.isInTemporaryLocation && !HelperClient.isReady {
                    Label("Move Change-Boot to the Applications folder first. The helper remembers where the app was when you installed it, so registering it from a build folder stops working after the next build.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Command line") {
                Text("Change-Boot can also be driven from Terminal: list the systems, switch, eject, read the log. Useful when the switch has to happen from a script or on a schedule.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: poleceniZainstalowane ? "terminal.fill" : "terminal")
                        .foregroundStyle(poleceniZainstalowane ? .green : .secondary)
                    Text(stanPolecenia)
                        .textSelection(.enabled)
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    if poleceniZainstalowane {
                        Button("Remove the command") { uruchom(CommandLineInstall.usun,
                                                              czynnosc: .usunieciePolecenia) }
                    } else {
                        Button("Install the command") { uruchom(CommandLineInstall.zainstaluj,
                                                                czynnosc: .instalacjaPolecenia) }
                    }
                }
                .disabled(busy)

                // Ścieżka do skopiowania — działa nawet bez dowiązania, więc nikt
                // nie zostaje z niczym, gdy nie chce wpuszczać programu do /usr/local/bin.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Without the command, the full path works too:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CommandLineInstall.cel)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Removing Change-Boot") {
                Text("Change-Boot puts three things outside its own app: the privileged helper, the change-boot command in /usr/local/bin, and — if you turned it on — a login item. Dragging the app to the Trash leaves all three behind, and the helper runs as root. Take them off here first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("You can also do this from Terminal, even after this window is gone: change-boot uninstall")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Remove everything installed") { pytanieOOdinstalowanie = true }
                        .disabled(busy || !Odinstalowanie.cokolwiekZainstalowane)
                }

                if let wynikOdinstalowania {
                    Text(wynikOdinstalowania)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("History") {
                switch historia {
                case .pusty:
                    Text("Nothing has happened yet. Switching a disk, ejecting one or installing the helper all leave a note here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                // 🔴 Trzeci przypadek istnieje od 0.2.6. Do 0.2.5 nieczytelny
                // dziennik wyglądał dokładnie tak samo jak pusty i program mówił
                // o obu „nic się nie wydarzyło" — czyli kłamał (P1-04 z audytu).
                case .nieczytelny(let powod):
                    Label("The event log is there, but could not be read. What the app did is not lost — it just cannot be shown here.\n\n\(powod)",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                case .wpisy(let wpisy):
                    ForEach(Array(wpisy.enumerated()), id: \.offset) { _, wpis in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: ikona(wpis.skutek))
                                .foregroundStyle(kolor(wpis.skutek))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(opis(wpis))
                                Text(formater.string(from: wpis.czas))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                // Awaria zapisu mówi się tutaj, spokojnie — nie oknem dialogowym.
                // Dziennik pisze się między innymi tuż przed restartem maszyny.
                if let awaria = EventLog.ostatniaAwaria {
                    Label("The last event could not be saved, so this list is incomplete.\n\n\(awaria.localizedDescription)",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text(EventLog.plik.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button("Show the log file") {
                        NSWorkspace.shared.activateFileViewerSelecting([EventLog.plik])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { historia = EventLog.przeczytaj(6) }
        .confirmationDialog(Text("Remove everything Change-Boot installed?"),
                            isPresented: $pytanieOOdinstalowanie,
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) { odinstaluj() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The privileged helper, the change-boot command and the login item come off. Your settings and the event log stay. macOS will ask for your password once, for the command in /usr/local/bin.")
        }
        .alert("Change-Boot", isPresented: Binding(
            get: { helperFailure != nil },
            set: { if !$0 { helperFailure = nil } })) {
            Button("OK", role: .cancel) { helperFailure = nil }
        } message: {
            Text(helperFailure ?? "")
        }
    }

    /// To samo co `run`, ale odświeża stan polecenia w terminalu i dziennik.
    private func uruchom(_ action: @escaping () throws -> Void,
                         czynnosc: EventLog.Czynnosc) {
        busy = true
        do {
            try action()
            EventLog.zapisz(czynnosc, skutek: .udane, zrodlo: .okno)
        } catch BootError.cancelled {
            EventLog.zapisz(czynnosc, skutek: .anulowane, zrodlo: .okno)
        } catch {
            helperFailure = error.localizedDescription
            EventLog.zapisz(czynnosc, skutek: .nieudane, zrodlo: .okno,
                            szczegol: error.localizedDescription)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            stanPolecenia = CommandLineInstall.opisStanu
            poleceniZainstalowane = CommandLineInstall.stan == .zainstalowane
            historia = EventLog.przeczytaj(6)
            busy = false
        }
    }

    /// Instalacja pomocnika ma **trzy** możliwe końce, nie dwa.
    ///
    /// `SMAppService.register()` rzuca `Operation not permitted` także wtedy, gdy
    /// rejestracja przeszła i macOS czeka tylko na kliknięcie „Zezwól" w swoim
    /// powiadomieniu. Do 0.2.2 program zapisywał w historii porażkę, a pomocnik
    /// po zgodzie działał — patrz `HelperClient.install`.
    private func zainstalujPomocnika() {
        busy = true
        do {
            let wynik = try HelperClient.install()
            EventLog.zapisz(.instalacjaPomocnika,
                            skutek: wynik == .gotowy ? .udane : .oczekuje,
                            zrodlo: .okno,
                            szczegol: wynik == .gotowy
                                ? nil
                                : String(localized: "waiting for approval in System Settings"))
        } catch {
            helperFailure = error.localizedDescription
            EventLog.zapisz(.instalacjaPomocnika, skutek: .nieudane, zrodlo: .okno,
                            szczegol: error.localizedDescription)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            helperStatus = HelperClient.statusDescription
            historia = EventLog.przeczytaj(6)
            busy = false
        }
    }

    /// Sprzątanie z okna. Melduje szczegółowo, a nie jednym „gotowe": czynność
    /// dotyka demona roota i katalogu systemowego, więc człowiek ma zobaczyć,
    /// co dokładnie zeszło, a co nie.
    private func odinstaluj() {
        busy = true
        let wynik = Odinstalowanie.wykonaj()

        func linia(_ co: String, _ stan: Odinstalowanie.Stan) -> String? {
            switch stan {
            case .zdjete:          return "✓ \(co)"
            case .nieBylo:         return nil
            case .nieudane(let p): return "✗ \(co) — \(p)"
            }
        }
        var linie = [
            linia(String(localized: "login item"), wynik.wpisLogowania),
            linia(String(localized: "privileged helper"), wynik.pomocnik),
            linia("/usr/local/bin/change-boot", wynik.polecenie),
        ].compactMap { $0 }

        if linie.isEmpty {
            linie = [String(localized: "There was nothing to remove.")]
        } else if wynik.wszystkoPoszlo && wynik.cokolwiekBylo {
            linie.append("")
            linie.append(String(localized: "Done. You can move Change-Boot to the Trash now — your settings and the event log stay where they are."))
        }
        wynikOdinstalowania = linie.joined(separator: "\n")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            helperStatus = HelperClient.statusDescription
            stanPolecenia = CommandLineInstall.opisStanu
            poleceniZainstalowane = CommandLineInstall.stan == .zainstalowane
            historia = EventLog.przeczytaj(6)
            busy = false
        }
    }

    private func run(_ action: @escaping () throws -> Void,
                     czynnosc: EventLog.Czynnosc) {
        busy = true
        do {
            try action()
            EventLog.zapisz(czynnosc, skutek: .udane, zrodlo: .okno)
        } catch {
            helperFailure = error.localizedDescription
            EventLog.zapisz(czynnosc, skutek: .nieudane, zrodlo: .okno,
                            szczegol: error.localizedDescription)
        }
        // Stan po rejestracji potrafi wejść z opóźnieniem — odczytujemy go z
        // `SMAppService`, a nie zakładamy, że skoro nie rzuciło, to jest włączony.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            helperStatus = HelperClient.statusDescription
            busy = false
        }
    }
}
