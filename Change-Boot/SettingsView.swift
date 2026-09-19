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
    @State private var zdarzenia: [EventLog.Entry] = []
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
        }
    }

    private func kolor(_ skutek: EventLog.Skutek) -> Color {
        switch skutek {
        case .udane:     return .green
        case .nieudane:  return .red
        case .anulowane: return .secondary
        case .oczekuje:  return .orange
        }
    }

    /// Zdanie po ludzku, nie surowe pola zapisu.
    private func opis(_ wpis: EventLog.Entry) -> String {
        let zrodlo = wpis.zrodlo == .wierszPolecen ? " (wiersz poleceń)" : ""
        switch wpis.czynnosc {
        case .przelaczenie:
            let cel = wpis.naSystem ?? "?"
            let czysty = (wpis.czystyStart ?? false) ? ", czysty start" : ""
            return "Przełączenie na „\(cel)”\(czysty)\(zrodlo)"
        case .wysuniecie:
            return "Wysunięcie „\(wpis.naSystem ?? "?")”\(zrodlo)"
        case .instalacjaPomocnika:
            return "Instalacja pomocnika\(zrodlo)"
        case .usunieciePomocnika:
            return "Usunięcie pomocnika\(zrodlo)"
        case .instalacjaPolecenia:
            return "Instalacja polecenia w terminalu\(zrodlo)"
        case .usunieciePolecenia:
            return "Usunięcie polecenia z terminala\(zrodlo)"
        case .uzbrojenieNaPowrot:
            return "Otwarcie po powrocie na ten system\(zrodlo)"
        }
    }

    var body: some View {
        @Bindable var configuration = model.configuration

        Form {
            Section("Switching") {
                Toggle("Clean start — do not reopen apps and windows",
                       isOn: $configuration.cleanStartByDefault)
            }

            Section("Menu bar icon") {
                Toggle("Show icon in the menu bar",
                       isOn: $configuration.showsMenuBarIcon)
                Toggle("Menu bar icon without colours",
                       isOn: $configuration.monochromeMenuBarIcon)
                    .disabled(!configuration.showsMenuBarIcon)
                Toggle("Hide the Dock icon when the window is closed",
                       isOn: $configuration.hidesDockIcon)
                    .disabled(!configuration.showsMenuBarIcon)
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
                Text("Switching from here sets a one-off login item on this system. Come back to it and Change-Boot is already open, ready to eject the disk you just arrived from. The item removes itself at that start.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Open Change-Boot at every login", isOn: $configuration.launchAtLogin)
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

            Section("History") {
                if zdarzenia.isEmpty {
                    Text("Nothing has happened yet. Switching a disk, ejecting one or installing the helper all leave a note here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(zdarzenia.enumerated()), id: \.offset) { _, wpis in
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

                HStack {
                    Spacer()
                    Button("Show the log file") {
                        NSWorkspace.shared.activateFileViewerSelecting([EventLog.plik])
                    }
                    .disabled(zdarzenia.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .task { zdarzenia = EventLog.ostatnie(6) }
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
            zdarzenia = EventLog.ostatnie(6)
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
                                : "czeka na zgodę w Ustawieniach systemowych")
        } catch {
            helperFailure = error.localizedDescription
            EventLog.zapisz(.instalacjaPomocnika, skutek: .nieudane, zrodlo: .okno,
                            szczegol: error.localizedDescription)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            helperStatus = HelperClient.statusDescription
            zdarzenia = EventLog.ostatnie(6)
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
