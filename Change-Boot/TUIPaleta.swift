import Foundation

/// Barwy interfejsu pełnoekranowego i dwie drogi ich zapisu.
///
/// Paleta przyszła od [U] 2026-09-19 i jest wiążąca. Zasada jej użycia też:
/// **kolor niesie znaczenie, nie dekorację**. Niebieski to zaznaczenie i główna
/// akcja, zielony gotowość, żółty ostrzeżenie, czerwony błąd, szary rzeczy
/// drugorzędne. Nie wolno mieszać kilku barw w jednym elemencie.
enum Paleta {

    static let tlo        = 0x0D0F12
    static let tekst      = 0xE6E8EB
    static let drugi      = 0x858B94
    static let ramka      = 0x30343B
    static let akcent     = 0x5E9EFF
    static let sukces     = 0x55D187
    static let ostrzezenie = 0xF2C94C
    static let blad       = 0xFF6B6B

    // MARK: - Zapis barwy

    /// 🔴 Dwie drogi, bo terminal [U] ma tylko jedną z nich.
    ///
    /// Zmierzone 2026-09-19: `infocmp -x xterm-256color` daje `colors#256`
    /// i **zero** trafień na `RGB`; Terminal.app 2.15 nie zgłasza koloru
    /// 24-bitowego. Paleta jest 24-bitowa, więc bez przybliżania do 256 kolorów
    /// wyglądałaby u [U] nie tak, jak ją zaprojektował — albo wcale.
    ///
    /// Wyboru dokonuje program sam, po `COLORTERM`; nie ma tu ustawienia
    /// do wyklikania, bo nie ma czego wybierać — terminal albo umie, albo nie.
    static func pisak(_ hex: Int) -> String { sekwencja(hex, tlo: false) }
    static func pedzel(_ hex: Int) -> String { sekwencja(hex, tlo: true) }

    static let zeruj = "\u{1B}[0m"
    static let pogrubienie = "\u{1B}[1m"

    private static func sekwencja(_ hex: Int, tlo: Bool) -> String {
        guard Terminal.czyKolor else { return "" }
        let r = (hex >> 16) & 0xFF, g = (hex >> 8) & 0xFF, b = hex & 0xFF
        let rola = tlo ? 48 : 38
        return Terminal.czyPelnyKolor
            ? "\u{1B}[\(rola);2;\(r);\(g);\(b)m"
            : "\u{1B}[\(rola);5;\(na256(r, g, b))m"
    }

    /// Najbliższy z 256 kolorów terminala.
    ///
    /// 🔴 **Nie zgaduje, który kandydat jest lepszy — mierzy.** Paleta 256 ma dwa
    /// rozłączne zbiory szarości: sześcian 6×6×6 (poziomy 0, 95, 135, 175, 215, 255)
    /// i drabinkę 232–255 (co ~10 poziomów). Pierwsza wersja wybierała między nimi
    /// progiem „różnica składowych mniejsza niż 8" i **myliła się**, bo barwy [U]
    /// są szarościami z lekkim błękitem, a nie czystymi:
    ///
    ///     #30343B = (48, 52, 59), różnica R–B wynosi 11
    ///       → próg odrzucał drabinkę, sześcian dawał poziom 1, czyli (95, 95, 95)
    ///       → obramowanie wychodziło DWA RAZY jaśniejsze, niż miało być
    ///
    /// Zamiast progu: policz obu kandydatów i weź bliższego. Miara to kwadrat
    /// odległości w RGB — prosta, bez pierwiastka, bo porównujemy tylko między sobą.
    /// Znalezione przez sprawdzian `Testy/terminal`, zanim ktokolwiek to zobaczył.
    static func na256(_ r: Int, _ g: Int, _ b: Int) -> Int {
        let (indeksSzescianu, barwaSzescianu) = zSzescianu(r, g, b)
        let (indeksDrabinki, barwaDrabinki) = zDrabinki(r, g, b)
        return odleglosc(barwaSzescianu, (r, g, b)) <= odleglosc(barwaDrabinki, (r, g, b))
            ? indeksSzescianu : indeksDrabinki
    }

    private static func odleglosc(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int {
        let dr = a.0 - b.0, dg = a.1 - b.1, db = a.2 - b.2
        return dr*dr + dg*dg + db*db
    }

    /// Sześcian 6×6×6, indeksy 16–231.
    private static func zSzescianu(_ r: Int, _ g: Int, _ b: Int) -> (Int, (Int, Int, Int)) {
        let pr = poziom(r), pg = poziom(g), pb = poziom(b)
        return (16 + 36*pr + 6*pg + pb, (wartoscPoziomu(pr), wartoscPoziomu(pg), wartoscPoziomu(pb)))
    }

    /// Drabinka szarości, indeksy 232–255. Krok to 10 poziomów, od 8 do 238.
    private static func zDrabinki(_ r: Int, _ g: Int, _ b: Int) -> (Int, (Int, Int, Int)) {
        let jasnosc = (r + g + b) / 3
        let krok = max(0, min(23, (jasnosc - 8 + 5) / 10))
        let wartosc = 8 + krok * 10
        return (232 + krok, (wartosc, wartosc, wartosc))
    }

    /// Jeden z sześciu poziomów sześcianu barw. Progi są takie, jakich używa
    /// sam xterm — nie równe szóstki.
    private static func poziom(_ wartosc: Int) -> Int {
        if wartosc < 48 { return 0 }
        if wartosc < 115 { return 1 }
        return min(5, (wartosc - 35) / 40)
    }

    /// Faktyczna składowa, którą terminal namaluje dla danego poziomu sześcianu.
    private static func wartoscPoziomu(_ poziom: Int) -> Int {
        poziom == 0 ? 0 : 55 + poziom * 40
    }

    // MARK: - Szerokość

    /// Ile kolumn zajmie napis na ekranie.
    ///
    /// Liczy **bez sekwencji sterujących** — te nie zajmują miejsca, a wpisane
    /// do `count` rozsypują każde dopełnienie i ramka przestaje się domykać.
    static func szerokosc(_ napis: String) -> Int {
        var suma = 0
        var wSekwencji = false
        for znak in napis {
            if znak == "\u{1B}" { wSekwencji = true; continue }
            if wSekwencji {
                if znak == "m" { wSekwencji = false }
                continue
            }
            suma += 1
        }
        return suma
    }
}
