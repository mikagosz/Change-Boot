import Foundation

/// Ustawienia narzucone z zewnątrz profilem konfiguracyjnym — warstwa MDM.
///
/// Po co: program dla jednej osoby przy jednym Macu konfiguruje się klikaniem.
/// Pracownia z czterdziestoma maszynami nie klika — dostaje od działu IT profil
/// `.mobileconfig`, a ten rozwozi ustawienia na wszystkie Maki naraz i **zamyka
/// je na klucz**, żeby pracownik ich nie przestawił.
///
/// 🔴 Dwie rzeczy, które trzeba wiedzieć, zanim się tu cokolwiek doda:
///
/// 1. **Nie `UserDefaults.standard`, tylko `CFPreferences`.** Profil ląduje w
///    `/Library/Managed Preferences/<domena>.plist` (poziom urządzenia) albo
///    `/Library/Managed Preferences/<użytkownik>/<domena>.plist`.
///    `CFPreferencesCopyAppValue` zna kolejność pierwszeństwa tych warstw i
///    oddaje właściwą wartość; `UserDefaults` w procesie bez pakietu programu
///    potrafi celować w cudzą domenę — patrz `AppBundle`.
/// 2. **„Jest wartość" to nie to samo co „jest narzucona".**
///    `CFPreferencesAppValueIsForced` odpowiada na drugie pytanie i tylko ono
///    decyduje, czy przełącznik w Opcjach ma być zablokowany. Bez tego
///    rozróżnienia ustawienie użytkownika wyglądałoby na politykę firmy.
///
/// Nazwy kluczy są **angielskie**, bo czyta je administrator w panelu MDM,
/// a nie użytkownik programu.
enum Polityka {

    /// Domena, w której szukamy narzuconych ustawień. Ta sama, w której program
    /// trzyma własne — profil ma nadpisywać ustawienia tego programu, nie cudze.
    static var domena: CFString {
        (AppBundle.identyfikator ?? "com.mikagosz.ChangeBoot") as CFString
    }

    // MARK: - Odczyt

    /// Czy wartość tego klucza jest **narzucona** profilem (a nie ustawiona
    /// przez użytkownika). Zablokowany przełącznik w Opcjach wisi na tej
    /// odpowiedzi i na niczym innym.
    static func narzucone(_ klucz: String) -> Bool {
        CFPreferencesAppValueIsForced(klucz as CFString, domena)
    }

    /// Wartość logiczna z profilu albo `nil`, gdy profil jej nie ustawia.
    ///
    /// Świadomie oddaje `nil`, a nie `false`: „profil nic nie mówi" i „profil
    /// mówi nie" to dwie różne odpowiedzi, a druga ma wygrywać z ustawieniem
    /// użytkownika. Zlanie ich w jedno kasowałoby cudze ustawienia przy każdym
    /// uruchomieniu na maszynie bez żadnego profilu.
    static func bool(_ klucz: String) -> Bool? {
        guard narzucone(klucz),
              let wartosc = CFPreferencesCopyAppValue(klucz as CFString, domena) else { return nil }
        return (wartosc as? NSNumber)?.boolValue
    }

    /// Lista napisów z profilu albo `nil`.
    static func napisy(_ klucz: String) -> [String]? {
        guard narzucone(klucz),
              let wartosc = CFPreferencesCopyAppValue(klucz as CFString, domena) else { return nil }
        return (wartosc as? [String])?.filter { !$0.isEmpty }
    }

    // MARK: - Klucze profilu

    enum Klucz {
        /// Lista UUID woluminów, z których **wolno** wystartować. Brak klucza
        /// znaczy „bez ograniczeń"; pusta lista znaczy „żadnego" i jest
        /// traktowana jak brak klucza — patrz `dozwoloneUUID`.
        static let dozwolone = "AllowedVolumeUUIDs"
        /// Przełączenie ma pytać o hasło administratora nawet z zainstalowanym
        /// pomocnikiem.
        static let hasloPrzyPrzelaczeniu = "RequireAdminForSwitch"
        /// Nazwa organizacji pokazywana w Opcjach, żeby użytkownik wiedział,
        /// kto mu ustawił zablokowane przełączniki.
        static let organizacja = "OrganizationName"
    }

    // MARK: - Reguły

    /// Woluminy, z których wolno startować, albo `nil` przy braku ograniczenia.
    ///
    /// 🔴 Pusta lista oddaje `nil`, czyli **brak ograniczenia**, a nie „nic nie
    /// wolno". Profil z pustą tablicą to prawie zawsze pomyłka administratora
    /// albo pozostałość po edycji — a reguła „nie wolno nic" zamurowuje maszynę
    /// na tym systemie, z którego akurat wystartowała, i nie ma jej jak cofnąć
    /// z tej maszyny. Bezpieczniejsza strona pomyłki jest tutaj.
    static var dozwoloneUUID: [String]? {
        guard let lista = napisy(Klucz.dozwolone), !lista.isEmpty else { return nil }
        return lista.map { $0.uppercased() }
    }

    /// Czy przełączenie ma iść przez okno hasła administratora.
    static var wymagajHasla: Bool { bool(Klucz.hasloPrzyPrzelaczeniu) ?? false }

    /// Nazwa organizacji z profilu, jeśli ją podała.
    static var organizacja: String? {
        guard narzucone(Klucz.organizacja),
              let wartosc = CFPreferencesCopyAppValue(Klucz.organizacja as CFString, domena),
              let nazwa = wartosc as? String, !nazwa.isEmpty else { return nil }
        return nazwa
    }

    /// Czy na tej maszynie w ogóle stoi jakiś profil dla tego programu.
    /// Opcje pokazują wtedy jedno zdanie wyjaśnienia zamiast milczeć.
    static var czyZarzadzany: Bool {
        dozwoloneUUID != nil
            || narzucone(Klucz.hasloPrzyPrzelaczeniu)
            || narzucone(Klucz.organizacja)
            || zarzadzaneUstawienia.contains { narzucone($0) }
    }

    /// Ustawienia programu, które profil może przejąć. Klucze te same, którymi
    /// posługuje się `Configuration` — profil nadpisuje dokładnie to, co
    /// użytkownik ustawiłby w Opcjach.
    static let zarzadzaneUstawienia = [
        Configuration.Key.menuBar,
        Configuration.Key.monoMenuBar,
        Configuration.Key.hideDock,
        Configuration.Key.cleanStart,
        Configuration.Key.launchAtLogin,
        Configuration.Key.launchAfterSwitch,
    ]

    /// Czy z tego woluminu wolno wystartować.
    ///
    /// Porównanie po UUID, nie po nazwie: nazwę dysku zmienia każdy w dwie
    /// sekundy, a reguła bezpieczeństwa oparta na czymś, co użytkownik sam
    /// przestawia, nie jest regułą.
    static func czyWolnoStartowac(_ system: BootSystem) -> Bool {
        czyNaLiscie(system.volumeUUID, dozwolone: dozwoloneUUID)
    }

    /// Sama reguła, odcięta od czytania profilu.
    ///
    /// 🔴 Osobno, żeby dało się ją **sprawdzić z listą w ręku**. Bez tego cały
    /// sprawdzian polityki byłby serią zer na maszynie bez profilu — a zero
    /// z sita, którego nikt nie zmusił do jedynki, znaczy „nie wiem", nie
    /// „działa". Tu kontrola dodatnia kosztuje jedno wywołanie.
    ///
    /// Porównanie wielkimi literami po obu stronach: UUID wpisany do profilu
    /// ręcznie bywa małymi, a `diskutil` oddaje wielkimi. Reguła bezpieczeństwa
    /// przepuszczająca albo blokująca zależnie od wielkości liter jest usterką,
    /// nie regułą.
    static func czyNaLiscie(_ uuid: String, dozwolone: [String]?) -> Bool {
        guard let dozwolone, !dozwolone.isEmpty else { return true }
        return dozwolone.contains { $0.uppercased() == uuid.uppercased() }
    }
}
