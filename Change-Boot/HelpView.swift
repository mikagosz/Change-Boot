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

    static var current: AppLanguage {
        guard let list = UserDefaults.standard.array(forKey: key) as? [String],
              let first = list.first else { return .system }
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

    @State private var language = AppLanguage.current
    /// Język z chwili otwarcia okna. Bez tego przycisk „Uruchom ponownie" byłby
    /// wyłączony zawsze: wybór zapisuje się od razu, więc `AppLanguage.current`
    /// zrównuje się z wyborem, zanim ktokolwiek zdąży w niego kliknąć.
    @State private var languageAtOpen = AppLanguage.current
    @State private var helperStatus = HelperClient.statusDescription
    @State private var helperFailure: String?
    @State private var busy = false

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
                            "Off by default, because it gets in the way while recording the screen. With it on, closing the window leaves the app running in the menu bar and takes it out of the Dock.")

                    Divider()

                    helperSection

                    Divider()

                    languageSection
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
        .alert("Change-Boot", isPresented: Binding(
            get: { helperFailure != nil },
            set: { if !$0 { helperFailure = nil } })) {
            Button("OK", role: .cancel) { helperFailure = nil }
        } message: {
            Text(helperFailure ?? "")
        }
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

    // MARK: - Pomocnik

    private var helperSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: HelperClient.isReady ? "lock.open" : "lock")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Password").font(.headline)
                    Text("Changing the startup disk needs administrator rights. Install the helper once and Change-Boot stops asking for your password on every switch.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(helperStatus)
                        .font(.callout)
                        .foregroundStyle(HelperClient.isReady ? .green : .secondary)
                }
            }

            if HelperClient.isInTemporaryLocation && !HelperClient.isReady {
                Label("Move Change-Boot to the Applications folder first. The helper remembers where the app was when you installed it, so registering it from a build folder stops working after the next build.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if HelperClient.status == .requiresApproval {
                    Button("Open System Settings") {
                        HelperClient.openLoginItemsSettings()
                    }
                }
                if HelperClient.isReady {
                    Button("Remove helper") { run(HelperClient.uninstall) }
                } else {
                    Button("Install helper") { run(HelperClient.install) }
                }
            }
            .disabled(busy)
        }
    }

    private func run(_ action: @escaping () throws -> Void) {
        busy = true
        do {
            try action()
        } catch {
            helperFailure = error.localizedDescription
        }
        // Stan po rejestracji potrafi wejść z opóźnieniem — odczytujemy go z
        // `SMAppService`, a nie zakładamy, że skoro nie rzuciło, to jest włączony.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            helperStatus = HelperClient.statusDescription
            busy = false
        }
    }

    // MARK: - Język

    private var languageSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "character.bubble")
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text("Language").font(.headline)
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: language) { _, new in
                    AppLanguage.apply(new)
                }
                Text("Change-Boot has to restart to load the other language.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Restart Change-Boot") { AppLanguage.relaunch() }
                    .disabled(language == languageAtOpen)
            }
        }
    }
}
