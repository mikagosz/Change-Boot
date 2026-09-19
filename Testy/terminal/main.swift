// Sprawdzian headless warstwy terminala i palety interfejsu pełnoekranowego.
//
//   cd "Xcode programy/Change-Boot"
//   swiftc -o /tmp/test-terminal Testy/terminal/main.swift \
//          Change-Boot/Terminal.swift Change-Boot/TUIPaleta.swift \
//          Change-Boot/TUI.swift Change-Boot/BootSystem.swift \
//          Change-Boot/DiskUtility.swift Change-Boot/CommandLineTool.swift \
//          Change-Boot/AppVersion.swift Change-Boot/AppBundle.swift \
//          Change-Boot/Configuration.swift Change-Boot/SystemColor.swift \
//          Change-Boot/EventLog.swift Change-Boot/BootActions.swift \
//          Change-Boot/PrivilegedShell.swift Change-Boot/HelperClient.swift \
//          Change-Boot/HelperProtocol.swift Change-Boot/LoginItem.swift \
//          Change-Boot/HelpView.swift Change-Boot/Odinstalowanie.swift \
//          Change-Boot/CommandLineInstall.swift && /tmp/test-terminal
//
// 🔴 Sprawdzian NIE wchodzi w tryb surowy i nie rysuje po ekranie. Bada rzeczy,
// które da się policzyć: przeliczanie barw, liczenie szerokości i to, czy
// przywracanie terminala jest bezpieczne do wołania w kółko.
//
// Czego tu NIE ma i mieć nie może: sprawdzenia, że po zabiciu programu terminal
// wraca do siebie. To wymaga prawdziwego pseudo-terminalu i osobnego procesu —
// opisane w planie jako test do wykonania ręcznie.

import Foundation

var awarie = 0
func sprawdz(_ opis: String, _ warunek: @autoclosure () -> Bool) {
    if warunek() { print("  ✓ \(opis)") } else { print("  ✗ \(opis)"); awarie += 1 }
}

print("Przywracanie terminala")

// Bez wejścia w tryb surowy `przywroc()` nie ma czego przywracać i MUSI być
// obojętne — leci z `atexit` i z obsługi sygnałów, czyli także wtedy, gdy
// program nigdy w tryb surowy nie wszedł.
Terminal.przywroc()
Terminal.przywroc()
sprawdz("przywracanie bez wejścia w tryb surowy nie wywraca programu", true)

// Sprawdzian chodzi z potokiem na wyjściu, więc to jest zarazem kontrola ujemna
// dla `czyTerminal`: tryb surowy NIE ma się włączyć.
sprawdz("tryb surowy nie włącza się, gdy wyjście nie jest terminalem",
        !Terminal.wejdzWTrybSurowy())

print("\nRozmiar okna")
let r = Terminal.rozmiar
sprawdz("rozmiar ma sensowne wartości, także bez terminala (80×24)",
        r.kolumny >= 20 && r.wiersze >= 5)

print("\nPrzeliczanie barw na 256 kolorów")

// 🔴 Sedno: paleta [U] stoi na szarościach, a sześcian 6×6×6 ma między czernią
// a bielą tylko sześć stopni. Bez osobnej drabinki szarości tło (#0D0F12)
// i obramowanie (#30343B) wpadłyby w ten sam kolor i ramka zniknęłaby w tle.
let tlo   = Paleta.na256(0x0D, 0x0F, 0x12)
let ramka = Paleta.na256(0x30, 0x34, 0x3B)
let drugi = Paleta.na256(0x85, 0x8B, 0x94)
let tekst = Paleta.na256(0xE6, 0xE8, 0xEB)
print("  tło=\(tlo)  ramka=\(ramka)  drugi=\(drugi)  tekst=\(tekst)")
sprawdz("tło i obramowanie NIE zlewają się w jeden kolor", tlo != ramka)
sprawdz("obramowanie i tekst drugorzędny też nie", ramka != drugi)
sprawdz("tekst drugorzędny i główny też nie", drugi != tekst)

/// Jaką barwę terminal NAPRAWDĘ namaluje dla danego indeksu 256-kolorowego.
/// Bez tego porównujemy numery z dwóch rozłącznych zbiorów, a to nic nie znaczy:
/// indeks 59 z sześcianu i indeks 235 z drabinki nie są „mniejszy i większy",
/// tylko dwie różne półki. Pierwsza wersja sprawdzianu porównywała same indeksy
/// i pytała o rzecz bez sensu — poprawione po tym, jak wskazała prawdziwą usterkę.
func barwa(_ indeks: Int) -> (Int, Int, Int) {
    if indeks >= 232 { let v = 8 + (indeks - 232) * 10; return (v, v, v) }
    let i = indeks - 16
    func w(_ p: Int) -> Int { p == 0 ? 0 : 55 + p * 40 }
    return (w(i / 36), w((i / 6) % 6), w(i % 6))
}
func jasnosc(_ indeks: Int) -> Int {
    let (r, g, b) = barwa(indeks); return (r + g + b) / 3
}

// 🔴 To jest sprawdzian, który złapał usterkę: #30343B (48,52,59) wpadało
// na sześcian i wychodziło jako (95,95,95) — dwa razy za jasno.
sprawdz("obramowanie #30343B nie robi się dwa razy jaśniejsze",
        abs(jasnosc(ramka) - 53) <= 12)
sprawdz("tło #0D0F12 zostaje prawie czarne", jasnosc(tlo) <= 24)
sprawdz("tekst główny #E6E8EB zostaje prawie biały", jasnosc(tekst) >= 220)
sprawdz("tekst drugorzędny #858B94 trafia w połowę drogi",
        abs(jasnosc(drugi) - 139) <= 15)
sprawdz("cztery szarości idą od najciemniejszej do najjaśniejszej",
        jasnosc(tlo) < jasnosc(ramka) && jasnosc(ramka) < jasnosc(drugi)
            && jasnosc(drugi) < jasnosc(tekst))

// Barwy znaczące mają NIE wpaść na drabinkę szarości — inaczej niebieski akcent
// wyszedłby szary i zniknęłaby cała zasada „kolor niesie znaczenie".
let akcent = Paleta.na256(0x5E, 0x9E, 0xFF)
let sukces = Paleta.na256(0x55, 0xD1, 0x87)
let blad   = Paleta.na256(0xFF, 0x6B, 0x6B)
print("  akcent=\(akcent)  sukces=\(sukces)  błąd=\(blad)")
sprawdz("akcent, sukces i błąd NIE lądują na drabince szarości",
        [akcent, sukces, blad].allSatisfy { $0 < 232 })
sprawdz("akcent, sukces i błąd to trzy różne kolory",
        Set([akcent, sukces, blad]).count == 3)

// Kontrola dodatnia dla samego przeliczania: skrajne wartości mają trafiać
// w znane indeksy sześcianu.
sprawdz("kontrola dodatnia — czysta czerwień to indeks 196",
        Paleta.na256(255, 0, 0) == 196)
sprawdz("kontrola dodatnia — czysta zieleń to indeks 46",
        Paleta.na256(0, 255, 0) == 46)

print("\nLiczenie szerokości napisu")

// 🔴 Bez tego ramka przestaje się domykać: sekwencje sterujące nie zajmują
// kolumn, ale mają znaki, więc `count` liczy je razem z treścią.
let goly = "Macintosh HD"
let ubrany = Paleta.pisak(Paleta.akcent) + goly + Paleta.zeruj
sprawdz("napis bez sekwencji liczy się normalnie", Paleta.szerokosc(goly) == 12)
sprawdz("sekwencje sterujące NIE liczą się do szerokości",
        Paleta.szerokosc(ubrany) == 12)
sprawdz("kontrola ujemna — surowe `count` faktycznie się myli",
        ubrany.count > 12)
sprawdz("sama sekwencja ma szerokość zero",
        Paleta.szerokosc(Paleta.pisak(Paleta.tekst)) == 0)
sprawdz("pusty napis ma szerokość zero", Paleta.szerokosc("") == 0)

print("\nSkładanie ekranu — czy ramka się domyka")

// 🔴 Ten sprawdzian istnieje, bo pierwsza wersja panelu miała dopełnienie
// rozsypane po pięciu wierszach i każdy mylił się o tę samą jedną kolumnę.
// Prawa krawędź stała o znak lewiej niż rogi. Na ekranie widać to od razu,
// ale zobaczyć można dopiero po zbudowaniu i uruchomieniu — a policzyć tutaj.
let atrapa = BootSystem(volumeUUID: "TEST-UUID", name: "Macintosh HD",
                        productVersion: "27.2", mountPoint: "/",
                        deviceIdentifier: "disk3s3s1", isInternal: true)
let wiersze = TUI.panel(atrapa)
let szerokosci = Set(wiersze.map { Paleta.szerokosc($0) })
print("  wierszy panelu: \(wiersze.count), szerokości: \(szerokosci.sorted())")
sprawdz("każdy wiersz panelu ma tę samą szerokość", szerokosci.count == 1)
sprawdz("szerokość zgadza się z zadeklarowaną", szerokosci.first == TUI.szerokosc + 6)

// Panel bez treści i z bardzo długą nazwą — dopełnienie nie może wyjść ujemne
// ani rozepchać wiersza.
let dlugi = BootSystem(volumeUUID: "X", name: String(repeating: "Bardzo Długa Nazwa ", count: 6),
                       productVersion: "27.2", mountPoint: "/",
                       deviceIdentifier: "disk1", isInternal: false)
let szerokosciDlugie = Set(TUI.panel(dlugi).map { Paleta.szerokosc($0) })
print("  przy nazwie na \(dlugi.name.count) znaków: \(szerokosciDlugie.sorted())")
sprawdz("bardzo długa nazwa NIE rozpycha panelu — nadal jedna szerokość",
        szerokosciDlugie == szerokosci)

sprawdz("pusty pas ma pełną szerokość",
        Paleta.szerokosc(TUI.pas()) == TUI.szerokosc + 6)

print("\nUmiejscowienie klatki w oknie")

// 🔴 Ten sprawdzian istnieje, bo widok „otwierał się bardzo nisko" — zgłoszone
// przez [U] 2026-09-19 zrzutem okna 85×52, na którym rysunek siedział przy
// samym dole. Klatka szła wtedy wiersz po wierszu, przez znak końca linii:
// każdy taki znak w ostatnim wierszu okna przewija terminal o jeden, a po
// powiększeniu okna Terminal.app dokłada puste wiersze u góry i widok zostaje
// przyklejony do dołu. Teraz każdy wiersz ma własny adres i policzyć to można
// tutaj, bez patrzenia na ekran.
let klatka = TUI.klatka(wysokosc: 52)

sprawdz("klatka zaczyna się od wyczyszczenia ekranu",
        klatka.hasPrefix(Terminal.wyczysc))
sprawdz("pierwszy wiersz rysunku jest PIERWSZYM wierszem okna",
        klatka.dropFirst(Terminal.wyczysc.count).hasPrefix(Terminal.wWierszu(1)))
sprawdz("w klatce nie ma ani jednego znaku końca linii",
        !klatka.contains("\n") && !klatka.contains("\r"))

// Ile wierszy klatka faktycznie zajmuje i czy któryś nie wyszedł poza okno.
func adresyWierszy(_ tekst: String) -> [Int] {
    var numery: [Int] = []
    var reszta = Substring(tekst)
    while let poczatek = reszta.range(of: "\u{1B}[") {
        reszta = reszta[poczatek.upperBound...]
        guard let koniec = reszta.firstIndex(of: "H") else { break }
        let srodek = reszta[..<koniec]
        // Adres wiersza wygląda tak: `w;1`. Cokolwiek innego to inna sekwencja.
        if srodek.hasSuffix(";1"), let w = Int(srodek.dropLast(2)) { numery.append(w) }
    }
    return numery
}

let adresy = adresyWierszy(klatka)
print("  wierszy w klatce: \(adresy.count), od \(adresy.first ?? -1) do \(adresy.last ?? -1)")
sprawdz("wiersze idą po kolei od 1 w górę",
        adresy == Array(1...adresy.count))
sprawdz("kontrola dodatnia — adresy w ogóle się znalazły", adresy.count > 10)

// Okno niższe od rysunku: klatka ma się URWAĆ, a nie przewinąć terminala.
let niska = TUI.klatka(wysokosc: 8)
let adresyNiskie = adresyWierszy(niska)
print("  przy oknie na 8 wierszy: \(adresyNiskie.count)")
sprawdz("przy niskim oknie klatka nie wychodzi poza ostatni wiersz",
        adresyNiskie.count <= 8 && (adresyNiskie.max() ?? 0) <= 8)
sprawdz("kontrola ujemna — pełna klatka jest wyższa niż 8 wierszy",
        adresy.count > 8)
sprawdz("okno o zerowej wysokości nie wywraca składania",
        adresyWierszy(TUI.klatka(wysokosc: 0)).isEmpty)

// Pasek klawiszy ma wymieniać wysuwanie. Do 0.2.14 widok pełnoekranowy jako
// jedyna z trzech dróg programu nie umiał odpiąć dysku — okno i wiersz poleceń
// umiały. Sprawdzamy na złożonej klatce, bo pasek składa się z katalogu ciągów
// i literówka w kluczu daje pusty napis, nie błąd kompilacji.
sprawdz("pasek klawiszy wymienia wysuwanie",
        klatka.contains(CommandLineTool.t("Eject")))
sprawdz("kontrola dodatnia — wymienia też klawisze, które były wcześniej",
        klatka.contains(CommandLineTool.t("Refresh"))
            && klatka.contains(CommandLineTool.t("Quit")))

print("\nZmiana rozmiaru okna")
sprawdz("bez sygnału nie ma zgłoszonej zmiany rozmiaru",
        Terminal.czyZmienionoRozmiar() == false)
sprawdz("adres wiersza ma kształt ESC[w;1H",
        Terminal.wWierszu(7) == "\u{1B}[7;1H")

print("\nWybór drogi koloru")
sprawdz("czyKolor odpowiada na NO_COLOR i TERM=dumb",
        Terminal.czyKolor == (ProcessInfo.processInfo.environment["NO_COLOR"] == nil
                              && (ProcessInfo.processInfo.environment["TERM"] ?? "") != "dumb"))

print("\nAwarie: \(awarie)")
exit(awarie == 0 ? 0 : 1)
