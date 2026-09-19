import Foundation
import ServiceManagement

/// Zdejmowanie wszystkiego, co program zakłada **poza własnym pakietem**.
///
/// 🔴 Po co osobny typ na trzy wywołania. Change-Boot zostawia na maszynie trzy
/// rzeczy, których skasowanie ikony nie rusza:
///
/// | co | gdzie | czyje |
/// |---|---|---|
/// | demon | launchd, domena systemowa | root |
/// | dowiązanie `change-boot` | `/usr/local/bin` | `root:wheel` |
/// | wpis logowania | Ustawienia → Obiekty logowania | użytkownika |
///
/// Do 0.2.7 zdjąć je dało się **tylko z wnętrza programu** — a więc nie dało się
/// wcale, gdy ktoś najpierw przeciągnął ikonę do Kosza. Zostawał zarejestrowany
/// demon roota wskazujący w pustkę i dowiązanie, którego użytkownik nie skasuje
/// bez hasła i bez wiedzy, że w ogóle tam jest. Znalezisko P1-06 z audytu
/// 2026-09-19.
///
/// Sprzątanie jest **jawne i szczegółowe**: mówi, co zdjęło, czego nie było
/// i czego nie udało się ruszyć. Jedna zbiorcza odpowiedź „gotowe" przy czynności
/// dotykającej roota jest za mało.
enum Odinstalowanie {

    /// Co się stało z jedną rzeczą.
    enum Stan {
        case zdjete
        case nieBylo
        case nieudane(String)
    }

    struct Wynik {
        var pomocnik: Stan
        var polecenie: Stan
        var wpisLogowania: Stan

        var wszystkoPoszlo: Bool {
            [pomocnik, polecenie, wpisLogowania].allSatisfy {
                if case .nieudane = $0 { return false }
                return true
            }
        }

        /// Czy cokolwiek w ogóle było do zdjęcia — żeby nie meldować sukcesu
        /// komuś, kto niczego nie instalował.
        var cokolwiekBylo: Bool {
            [pomocnik, polecenie, wpisLogowania].contains {
                if case .zdjete = $0 { return true }
                return false
            }
        }
    }

    /// Czy jest w ogóle co sprzątać. Czytane przez okno, żeby nie pokazywać
    /// przycisku, który nic nie zrobi.
    static var cokolwiekZainstalowane: Bool {
        HelperClient.status != .notRegistered
            || CommandLineInstall.stan != .brak
            || LoginItem.wlaczony
            || LoginItem.czekaNaZgode
    }

    /// Zdejmuje wszystko po kolei. **Nie przerywa się na pierwszym błędzie** —
    /// nieudane zdjęcie demona nie może zostawić dowiązania, skoro dowiązanie
    /// dałoby się zdjąć.
    ///
    /// Kolejność jest celowa: najpierw rzeczy, które nie proszą o hasło, na końcu
    /// dowiązanie. Kto przerwie na oknie hasła, zdąży już zdjąć demona.
    static func wykonaj() -> Wynik {
        var wynik = Wynik(pomocnik: .nieBylo, polecenie: .nieBylo, wpisLogowania: .nieBylo)

        // 1. Wpis logowania — bez hasła, bez pytania.
        if LoginItem.wlaczony || LoginItem.czekaNaZgode {
            do {
                try LoginItem.ustaw(false)
                wynik.wpisLogowania = .zdjete
            } catch {
                wynik.wpisLogowania = .nieudane(error.localizedDescription)
            }
        }
        AppBundle.defaults.set(false, forKey: Configuration.Key.armedOnce)

        // 2. Demon. `unregister` na niezarejestrowanym rzuca — stąd sprawdzenie stanu.
        if HelperClient.status != .notRegistered {
            do {
                try HelperClient.uninstall()
                wynik.pomocnik = .zdjete
            } catch {
                wynik.pomocnik = .nieudane(error.localizedDescription)
            }
        }

        // 3. Dowiązanie w katalogu systemowym — to ono prosi o hasło.
        //    Kasujemy je także wtedy, gdy wskazuje na INNĄ kopię programu:
        //    sprzątamy po sobie, a nie po dokładnie tej ścieżce.
        if CommandLineInstall.stan != .brak {
            do {
                try CommandLineInstall.usun()
                wynik.polecenie = .zdjete
            } catch BootError.cancelled {
                wynik.polecenie = .nieudane(String(localized: "You cancelled the password prompt."))
            } catch {
                wynik.polecenie = .nieudane(error.localizedDescription)
            }
        }

        return wynik
    }

    /// Co zostaje **mimo** sprzątania i co z tym zrobić ręcznie.
    ///
    /// Ustawienia i dziennik zostają świadomie: to dane użytkownika, a program
    /// nie kasuje cudzych danych przy odinstalowaniu. Ma o nich tylko powiedzieć.
    static var coZostaje: [String] {
        [EventLog.katalog.path,
         "~/Library/Preferences/\(AppBundle.identyfikator ?? "com.mikagosz.ChangeBoot").plist"]
    }
}
