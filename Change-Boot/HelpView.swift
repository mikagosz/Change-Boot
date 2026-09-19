import AppKit
import SwiftUI

/// Język interfejsu wybrany ręcznie.
///
/// macOS sam nie daje przełącznika języka **w** programie — jest tylko lista
/// „Języki i region" w Ustawieniach, o której trzeba wiedzieć. Program niesie
/// polski i angielski, więc wybór stoi tam, gdzie go szukać: w oknie programu.
///
/// Działa to przez `AppleLanguages` w przegródce programu: ten sam mechanizm,
/// którego używają Ustawienia, tylko zapisany pod własnym bundle ID. Nic poza
/// własną przegródką nie jest ruszane.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case polish
    case english

    var id: String { rawValue }

    /// Kod dla `AppleLanguages`; `nil` znaczy „bez nadpisania, jak w systemie".
    var code: String? {
        switch self {
        case .system:  return nil
        case .polish:  return "pl"
        case .english: return "en"
        }
    }

    var label: String {
        switch self {
        case .system:  return String(localized: "Follow system")
        case .polish:  return "Polski"
        case .english: return "English"
        }
    }

    private static let key = "AppleLanguages"

    /// 🔴 Czytamy **własną przegródkę**, nie `UserDefaults.standard.array(forKey:)`.
    ///
    /// Zwykły odczyt przechodzi przez całą listę domen, razem z globalną, a tam
    /// `AppleLanguages` stoi zawsze — u [U] `("pl-PL")`. Program bez własnego
    /// ustawienia wyglądał przez to na ustawiony na polski i ptaszek w menu siadał
    /// przy „Polski" zamiast przy „Jak w systemie". Zmierzone 2026-09-19:
    /// `defaults read com.mikagosz.ChangeBoot AppleLanguages` → klucza nie ma,
    /// a `current` zwracało `.polish`.
    static var current: AppLanguage {
        let domain = Bundle.main.bundleIdentifier ?? ""
        guard let own = UserDefaults.standard.persistentDomain(forName: domain)?[key] as? [String],
              let first = own.first else { return .system }
        if first.hasPrefix("pl") { return .polish }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    static func apply(_ language: AppLanguage) {
        if let code = language.code {
            UserDefaults.standard.set([code], forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Wymiana języka wymaga ponownego uruchomienia: zasoby językowe wczytują się
    /// raz, przy starcie procesu. Program uruchamia się sam, żeby nie zostawiać
    /// użytkownika z poleceniem „zamknij i otwórz".
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// Krótka instrukcja: co który element robi i czego się po nim spodziewać.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("How Change-Boot works").font(.title3).bold()
                Spacer()
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("internaldrive", "The list",
                            "Every macOS installation you added sits here, remembered by the volume's UUID — not by its name. Rename the disk and the entry follows. Unplug it and the entry stays, greyed out, because an unplugged disk is no reason to forget your settings.")

                    section("paintpalette", "The colours",
                            "Each system gets its own colour so you can tell them apart at a glance. Click the disk icon in a row to change it. The colour is stored with the entry, so an unplugged disk keeps it, only dimmed.")

                    section("arrow.triangle.2.circlepath", "Switch",
                            "Sets the startup disk, checks that the firmware really accepted it, and only then restarts. If the check fails, nothing restarts — the Mac would have booted the wrong system.")

                    section("sparkles", "Clean start",
                            "On: your apps and windows do not come back after the restart. Off: macOS reopens them, the same as the “Reopen windows when logging back in” checkbox in the system restart dialog.")

                    section("eject", "Eject",
                            "Ejects the whole physical disk, not just the volume you see in Finder. Finder leaves the hidden data volume mounted, which is why unplugging after a Finder eject makes macOS complain that the disk was not ejected properly.")

                    section("menubar.arrow.up.rectangle", "Menu bar icon",
                            "Off by default, because it gets in the way while recording the screen. With it on, closing the window leaves the app running in the menu bar instead of quitting, and you can have it leave the Dock as well. Its colours can be stripped too, from the icon's own menu, so it looks like the rest of the menu bar and follows light and dark mode on its own.")

                    Divider()

                    section("character.bubble", "Language",
                            "Change-Boot speaks Polish and English. Pick the language in Options, in the Change-Boot menu at the top of the screen, or in the menu bar icon. The app restarts when you change it, because the language is loaded once, when the app starts.")

                    Divider()

                    section("gearshape", "Options",
                            "Every setting lives in the Options window — the gear button at the bottom of the main window, or Command-comma. That is also where you install the helper that stops macOS asking for your password on every switch.")
                }
                .padding(16)
            }

            Divider()

            HStack {
                Text(AppVersion.withName).font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 560)
    }

    private func section(_ symbol: String, _ title: LocalizedStringKey,
                         _ body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Podmenu wyboru języka, to samo w dwóch menu.
///
/// Stoi w górnym menu programu (obok „O programie") **i** w menu ikony w pasku.
/// Dwa miejsca są celowe: ikona w pasku jest domyślnie wyłączona, więc sama
/// zostawiłaby wybór niedostępnym; górne menu widać tylko wtedy, gdy program jest
/// na wierzchu, więc samo nie starczy, gdy ktoś pracuje z paska.
///
/// Wybór działa od razu i od razu uruchamia program ponownie — język wczytuje się
/// raz, przy starcie procesu, więc „wybrałem i nic się nie stało" byłoby gorsze
/// niż restart bez pytania.
struct LanguageMenu: View {
    var body: some View {
        Menu("Language") {
            // `Toggle` rysuje w menu natywny ptaszek przy wybranej pozycji i nie
            // dokłada własnego nagłówka. `Picker(.inline)` też daje ptaszki, ale
            // powtarza etykietę w środku podmenu — wychodzi „Język → Język".
            ForEach(AppLanguage.allCases) { option in
                Toggle(option.label, isOn: Binding(
                    get: { AppLanguage.current == option },
                    set: { wybrane in
                        guard wybrane, option != AppLanguage.current else { return }
                        AppLanguage.apply(option)
                        AppLanguage.relaunch()
                    }))
            }
        }
    }
}
