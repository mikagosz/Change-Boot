import Foundation
import ServiceManagement

/// Uruchamianie Change-Boota przy logowaniu — na stałe albo jednorazowo.
///
/// Dwa ustawienia, bo to dwie różne potrzeby [U] z 2026-09-19:
///
/// 1. **Powrót po przełączeniu.** *„jeżeli przełączamy się między deskami używając
///    naszego narzędzia, to przy powrocie do dysku HD nasza aplikacja się też
///    uruchomi, żeby móc sobie swobodnie odmontować dysk"*. Program włącza się sam
///    jeden raz, po powrocie, i znowu się wypisuje.
///
/// 2. **Autostart.** Zwykły wpis logowania dla kogoś, kto chce mieć program
///    pod ręką zawsze.
///
/// 🔴 **Dlaczego jednorazowe uzbrojenie działa, choć wygląda na odwrotne.**
/// Wpis logowania jest własnością **tej** instalacji macOS, a nie dysku, na który
/// przechodzimy. Uzbrojenie przed restartem zapisuje się więc na systemie, który
/// właśnie opuszczamy — i odpala się dokładnie wtedy, gdy na niego wrócimy.
/// Systemu po drugiej stronie ten program nie rusza i ruszać nie ma; tam decyduje
/// tamtejsza kopia Change-Boota i jej własne ustawienie.
///
/// Uzbrojenie **nie może przerwać przełączenia**. Wpis logowania jest wygodą,
/// a przestawienie dysku startowego zadaniem — dlatego błąd rejestracji ląduje
/// w dzienniku i na tym koniec.
enum LoginItem {

    private static var usluga: SMAppService { .mainApp }

    static var wlaczony: Bool { usluga.status == .enabled }

    /// Czy system czeka na zgodę użytkownika w Ustawieniach → Obiekty logowania.
    static var czekaNaZgode: Bool { usluga.status == .requiresApproval }

    static func ustaw(_ wlaczony: Bool) throws {
        if wlaczony {
            guard usluga.status != .enabled else { return }
            try usluga.register()
        } else {
            guard usluga.status == .enabled || usluga.status == .requiresApproval else { return }
            try usluga.unregister()
        }
    }

    // MARK: - Jednorazowe uzbrojenie na powrót

    /// Wywoływane **przed** restartem, gdy ustawienie „otwórz po powrocie" jest włączone.
    ///
    /// Nie rzuca: przełączenie dysku ma się odbyć nawet wtedy, gdy wpisu logowania
    /// nie udało się założyć.
    static func uzbrojNaPowrot() {
        // Autostart już to załatwia — drugi raz nie ma czego włączać i nie ma
        // czego rozbrajać po starcie.
        guard !AppBundle.defaults.bool(forKey: Configuration.Key.launchAtLogin) else { return }
        guard usluga.status != .enabled else { return }
        do {
            try usluga.register()
            AppBundle.defaults.set(true, forKey: Configuration.Key.armedOnce)
        } catch {
            EventLog.zapisz(.uzbrojenieNaPowrot, skutek: .nieudane, zrodlo: .okno,
                            szczegol: error.localizedDescription)
        }
    }

    /// Wywoływane przy starcie programu: zdejmuje wpis założony jednorazowo.
    ///
    /// Kolejność ma znaczenie — znacznik kasujemy **przed** wypisaniem, żeby
    /// nieudane wyrejestrowanie nie zostawiło programu w pętli prób przy każdym
    /// kolejnym starcie.
    static func rozbrojPoStarcie() {
        let ustawienia = AppBundle.defaults
        guard ustawienia.bool(forKey: Configuration.Key.armedOnce) else { return }
        ustawienia.set(false, forKey: Configuration.Key.armedOnce)
        guard !ustawienia.bool(forKey: Configuration.Key.launchAtLogin) else { return }
        try? usluga.unregister()
    }
}
