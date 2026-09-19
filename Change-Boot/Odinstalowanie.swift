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

    /// Nazwa przegródki, której nie powinno być.
    ///
    /// 🔴 Powstała przez usterkę 14: do 0.2.2 wiersz poleceń uruchomiony przez
    /// dowiązanie `/usr/local/bin/change-boot` nie widział własnego pakietu,
    /// więc `UserDefaults` nazwał domenę po **procesie** — `change-boot` —
    /// zamiast po identyfikatorze pakietu. 0.2.3 naprawiła przyczynę, ale
    /// plik, który już powstał, leży dalej: na maszynie [U] z ramką okna
    /// w środku. Znalezisko P3-17 z audytu 2026-09-19.
    static let osieroconaDomena = "change-boot"

    /// Kasuje osieroconą przegródkę po wpadce 0.2.2. Wolno wołać zawsze.
    ///
    /// 🔴 Przez `removePersistentDomain`, a nie przez skasowanie pliku. Plikami
    /// w `~/Library/Preferences` rządzi `cfprefsd` i trzyma je w pamięci —
    /// usunięty spod jego nosa potrafi wrócić przy następnym zapisie cache'u.
    /// Ta droga mówi mu wprost: tej domeny nie ma.
    ///
    /// To **nie są** dane użytkownika, tylko nasze śmieci, więc lecą bez pytania.
    /// Ustawienia programu siedzą w domenie nazwanej identyfikatorem pakietu
    /// i tej nikt tu nie rusza — patrz `coZostaje`.
    /// Zwraca `true`, gdy faktycznie było co skasować.
    ///
    /// 🔴 **Bez parametru z nazwą domeny i tak ma zostać.** Pierwsza wersja
    /// przyjmowała nazwę „żeby dało się to sprawdzić na własnej przegródce"
    /// — i sprawdzian, uruchomiony bez pakietu, podał jej prawdziwą domenę
    /// programu. `removePersistentDomain` skasowało ustawienia [U]: listę
    /// systemów, język, ikonę paska. Zapora niżej nie pomogła, bo binarka
    /// sprawdzianu nie ma identyfikatora pakietu, więc nie miała się z czym
    /// porównać. Funkcja, która umie skasować dowolną domenę, prędzej czy
    /// później dostanie złą — więc nie umie.
    @discardableResult
    static func sprzatnijOsieroconaPrzegrodke() -> Bool {
        // Zapora na wypadek zmiany identyfikatora pakietu na tę samą nazwę:
        // program nie ma prawa skasować własnych ustawień.
        guard AppBundle.identyfikator != osieroconaDomena else { return false }
        // 🔴 `!= nil` tu nie wystarczy. Zmierzone: po `removePersistentDomain`
        // odpytanie w TYM SAMYM procesie oddaje pusty słownik, nie `nil` —
        // domena zostaje zarejestrowana, choć nic w niej nie ma. Sprawdzamy
        // więc zawartość, bo pusta przegródka to nie jest „coś do sprzątania".
        guard let zawartosc = UserDefaults.standard.persistentDomain(forName: osieroconaDomena),
              !zawartosc.isEmpty else { return false }
        UserDefaults.standard.removePersistentDomain(forName: osieroconaDomena)

        // Plik po domenie kasujemy na dokładkę, ale bez obietnicy.
        //
        // 🔴 Zmierzone 2026-09-19, z uczciwym czekaniem: po `removePersistentDomain`
        // plik `~/Library/Preferences/change-boot.plist` zostaje **pusty**
        // (42 bajty, `{}`), a skasowany — **wraca po około trzech sekundach**,
        // odtworzony przez `cfprefsd` po wyjściu procesu. Pierwszy pomiar mówił
        // co innego, bo czekał dwie sekundy: sito bez kontroli dodatniej.
        //
        // Ścigać się z `cfprefsd` nie ma po co. Rzeczą, o którą tu chodzi, jest
        // **treść** — ramka okna po wpadce 0.2.2 — i ta znika na pewno. Pusta
        // skorupka po pliku nic nie niesie. Kasowanie zostaje, bo czasem trafia
        // w chwilę, gdy nikt już tej domeny nie trzyma, a zaszkodzić nie może.
        let plik = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/\(osieroconaDomena).plist")
        try? FileManager.default.removeItem(at: plik)
        return true
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
