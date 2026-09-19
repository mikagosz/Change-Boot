import Foundation

/// Numer wersji w jednym kształcie na cały program.
///
/// Stoi osobno, bo pokazują go trzy miejsca — stopka okna, kreator i Pomoc —
/// a trzy kopie tego samego formatowania rozjeżdżają się po cichu przy pierwszej
/// zmianie. Numer budowania świadomie **nie wchodzi**: to liczba dla Xcode,
/// nie dla patrzącego na okno.
enum AppVersion {
    /// Na przykład `v.0.1.11`.
    ///
    /// Numer idzie z `AppBundle`, nie z `Bundle.main`: uruchomiony przez dowiązanie
    /// `change-boot` proces nie ma pakietu pod ścieżką procesu i wypisywał `v.?`.
    static var short: String {
        "v.\(AppBundle.wersja ?? "?")"
    }

    /// Na przykład `Change-Boot v.0.1.11`.
    static var withName: String { "Change-Boot \(short)" }
}
