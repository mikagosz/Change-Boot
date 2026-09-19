import Foundation

/// Pakiet programu i jego przegródka ustawień — odporne na uruchomienie binarki
/// spoza pakietu.
///
/// 🔴 **`Bundle.main` tego nie załatwia.** Pakiet rozpoznaje się po ścieżce procesu,
/// a ta przy uruchomieniu przez dowiązanie `change-boot` w `/usr/local/bin` brzmi
/// `/usr/local/bin/change-boot` — katalog bez `Info.plist`. Cały program widzi
/// wtedy „brak pakietu": nie ma numeru wersji, nie ma własnej domeny ustawień,
/// nie ma zasobów językowych.
///
/// Zmierzone 2026-09-19 na `0.2.2`, trzy skutki naraz:
/// - `change-boot --version` → `v.?`
/// - `change-boot list` → „Żaden system nie jest skonfigurowany", choć w oknie
///   stały dwa — bo `UserDefaults.standard` schodziło do domeny nazwanej po
///   procesie, nie po `com.mikagosz.ChangeBoot`
/// - gołe `change-boot` otwierało okno **po angielsku i od kreatora**
///
/// Rozwiązanie: rozwinąć dowiązanie i wejść w górę do pierwszego katalogu `.app`.
enum AppBundle {

    /// Pakiet `Change-Boot.app`, także gdy binarkę odpalono przez dowiązanie.
    ///
    /// Gdy pakietu nie da się znaleźć (sprawdziany headless kompilowane
    /// `swiftc`-iem), zostaje `Bundle.main` i wszystko zachowuje się jak dotąd.
    static let main: Bundle = {
        if Bundle.main.bundleIdentifier != nil { return Bundle.main }

        let sciezka = Bundle.main.executableURL?.path ?? CommandLine.arguments.first
        guard let sciezka, !sciezka.isEmpty else { return Bundle.main }

        var katalog = URL(fileURLWithPath: sciezka)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        while katalog.path != "/" {
            if katalog.pathExtension == "app", let pakiet = Bundle(url: katalog) {
                return pakiet
            }
            katalog = katalog.deletingLastPathComponent()
        }
        return Bundle.main
    }()

    /// Numer wersji z `Info.plist` pakietu programu.
    static var wersja: String? {
        main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    static var identyfikator: String? { main.bundleIdentifier }

    /// Przegródka ustawień programu — ta sama, którą widzi okno.
    ///
    /// W roli okna `Bundle.main` **jest** pakietem programu, więc zostaje zwykłe
    /// `UserDefaults.standard`: podstawianie wtedy własnej instancji po nazwie
    /// domeny nic nie daje, a gubi ustawienia podstawione przez sprawdziany.
    /// Dopiero gdy proces chodzi spoza pakietu, sięgamy po domenę z nazwy.
    static let defaults: UserDefaults = {
        guard main !== Bundle.main,
              let id = main.bundleIdentifier,
              let wlasne = UserDefaults(suiteName: id) else { return .standard }
        return wlasne
    }()
}
