// Sprawdzian headless wykrywania systemów i łańcucha dysków.
//
//   cd "Xcode programy/Change-Boot"
//   swiftc -o /tmp/test-wykrywanie Testy/wykrywanie/main.swift \
//          Change-Boot/DiskUtility.swift Change-Boot/BootSystem.swift \
//          Change-Boot/Kondycja.swift Change-Boot/CommandLineTool.swift \
//          Change-Boot/AppVersion.swift Change-Boot/AppBundle.swift \
//          Change-Boot/Configuration.swift Change-Boot/SystemColor.swift \
//          Change-Boot/EventLog.swift Change-Boot/BootActions.swift \
//          Change-Boot/PrivilegedShell.swift Change-Boot/HelperClient.swift \
//          Change-Boot/HelperProtocol.swift Change-Boot/LoginItem.swift \
//          Change-Boot/HelpView.swift Change-Boot/Odinstalowanie.swift \
//          Change-Boot/CommandLineInstall.swift Change-Boot/TUI.swift \
//          Change-Boot/TUIPaleta.swift Change-Boot/Terminal.swift \
//          Change-Boot/Polityka.swift && /tmp/test-wykrywanie
//
// Czyta prawdziwe dyski tej maszyny — bez fixture'ów, bo sprawdzane jest właśnie
// to, czy odczyt zgadza się z rzeczywistością. Wymaga co najmniej jednego
// systemu zewnętrznego; bez podłączonego dysku część sprawdzianów jest pomijana.

import Foundation

var awarie = 0
var pominiete = 0

func sprawdz(_ opis: String, _ warunek: @autoclosure () -> Bool) {
    if warunek() {
        print("  ✓ \(opis)")
    } else {
        print("  ✗ \(opis)")
        awarie += 1
    }
}

func pomin(_ opis: String, _ powod: String) {
    print("  — \(opis)  (pominięte: \(powod))")
    pominiete += 1
}

print("Wykrywanie systemów")

let systemy = SystemScanner.scan()
sprawdz("znaleziono jakikolwiek system", !systemy.isEmpty)

guard let biezacy = SystemScanner.current() else {
    print("  ✗ brak bieżącego systemu — dalsze sprawdziany bez sensu")
    exit(1)
}

sprawdz("bieżący system ma nazwę", !biezacy.name.isEmpty)
sprawdz("bieżący system ma UUID", !biezacy.volumeUUID.isEmpty)
sprawdz("bieżący system ma wersję macOS", !biezacy.productVersion.isEmpty)
sprawdz("bieżący system jest pierwszy na liście", systemy.first?.volumeUUID == biezacy.volumeUUID)

// Kontrola dodatnia: zanim uwierzymy, że czegoś nie ma, sprawdźmy, że sito
// w ogóle łapie coś, co na pewno istnieje.
sprawdz("wolumin główny ma SystemVersion.plist",
        SystemScanner.productVersion(atVolume: "/") != nil)
sprawdz("katalog bez systemu nie jest brany za system",
        SystemScanner.system(atVolume: "/tmp") == nil)

// USTERKA 2026-09-19: Cryptex Apple ma SystemVersion.plist z PUSTYM ProductVersion
// i trafił na listę systemów startowych jako „macOS" bez numeru.
sprawdz("wolumin niebootowalny nie jest systemem",
        SystemScanner.system(atVolume: "/System/Volumes/Preboot") == nil)
sprawdz("wolumin spoza / i /Volumes nie jest systemem",
        SystemScanner.system(atVolume: "/System/Volumes/Data") == nil)
sprawdz("każdy znaleziony system ma niepustą wersję",
        systemy.allSatisfy { !$0.productVersion.trimmingCharacters(in: .whitespaces).isEmpty })
sprawdz("każdy znaleziony system leży w / albo /Volumes",
        systemy.allSatisfy { $0.mountPoint == "/" || $0.mountPoint.hasPrefix("/Volumes/") })

print("\nTożsamość nie opiera się na nazwie")
sprawdz("UUID-y są unikalne",
        Set(systemy.map(\.volumeUUID)).count == systemy.count)

print("\nŁańcuch do dysku fizycznego")
if let zewnetrzny = systemy.first(where: { !$0.isInternal }) {
    print("  (dysk zewnętrzny: „\(zewnetrzny.name)” — macOS \(zewnetrzny.productVersion))")

    let nosnik = zewnetrzny.wholeDisk
    sprawdz("system zewnętrzny wskazuje dysk fizyczny", nosnik != nil)

    if let nosnik {
        // Kontener jest dyskiem syntetycznym; nośnik musi być czymś innym.
        let kontener = DiskUtility.string(zewnetrzny.mountPoint, "APFSContainerReference")
        sprawdz("nośnik to nie kontener APFS (\(nosnik) ≠ \(kontener ?? "?"))",
                nosnik != kontener)
        sprawdz("nośnik jest zewnętrzny",
                DiskUtility.bool(nosnik, "Internal") == false)
        sprawdz("nośnik da się wysunąć",
                DiskUtility.bool(nosnik, "Ejectable") == true)
    }

    let woluminy = DiskUtility.mountedVolumes(inContainerOf: zewnetrzny.mountPoint)
    sprawdz("kontener zgłasza więcej niż sam wolumin systemowy", woluminy.count > 1)
    sprawdz("lista zawiera wolumin systemowy", woluminy.contains(zewnetrzny.mountPoint))

    // Sedno sprawy: wolumin danych jest montowany z „nobrowse", więc Finder go
    // nie widzi i nie wysuwa. Ta lista musi go widzieć.
    let widoczneWFinderze = FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: nil, options: .skipHiddenVolumes)?.map(\.path) ?? []
    let ukryte = woluminy.filter { !widoczneWFinderze.contains($0) }
    sprawdz("widać wolumin ukryty przed Finderem (\(ukryte.joined(separator: ", ")))",
            !ukryte.isEmpty)
} else {
    pomin("łańcuch do dysku fizycznego", "brak podłączonego systemu zewnętrznego")
}

print("\nZnalezione systemy:")
for s in systemy {
    let gdzie = s.isInternal ? "wewnętrzny" : "zewnętrzny"
    let teraz = s.volumeUUID == biezacy.volumeUUID ? "  ← bieżący" : ""
    print("  \(s.name) — macOS \(s.productVersion), \(gdzie), \(s.deviceIdentifier)\(teraz)")
}

print("\nPrzegląd woluminów i kondycji")

let przeglad = Kondycja.przeglad()
print("  woluminów w przeglądzie: \(przeglad.count)")
sprawdz("przegląd zawiera wolumin, z którego maszyna pracuje",
        przeglad.contains { $0.punktMontowania == "/" })
sprawdz("kontrola dodatnia — każdy wolumin ma nazwę i punkt montowania",
        przeglad.allSatisfy { !$0.nazwa.isEmpty && !$0.punktMontowania.isEmpty })

// 🔴 To jest cała treść poprawki z 2026-09-19: żaden wolumin nie ma prawa
// pokazywać pojemności bez wolnego miejsca. Pierwsza wersja liczyła tylko
// `volumeAvailableCapacityForImportantUsage`, a ten oddaje ZERO dla udziałów
// sieciowych i dla zapieczętowanego woluminu systemowego — raport mówił wtedy
// „? wolne" i „zero KB" o woluminach, na których miejsca jest setki gigabajtów.
let bezMiejsca = przeglad.filter { $0.pojemnosc != nil && ($0.wolne ?? 0) <= 0 }
sprawdz("każdy wolumin o znanej pojemności ma też znane wolne miejsce",
        bezMiejsca.isEmpty)
if !bezMiejsca.isEmpty {
    print("     bez wolnego: \(bezMiejsca.map(\.nazwa))")
}

// Sito hydrauliki APFS-a. Punkty montowania są stałe w macOS, więc da się je
// sprawdzić wprost, bez zgadywania po tym, co akurat jest zamontowane.
sprawdz("korzeń jest widoczny dla człowieka", Kondycja.czyWidocznyDlaCzlowieka("/"))
sprawdz("dysk pod /Volumes też", Kondycja.czyWidocznyDlaCzlowieka("/Volumes/Cokolwiek"))
sprawdz("hydraulika APFS-a jest ukryta",
        !Kondycja.czyWidocznyDlaCzlowieka("/System/Volumes/VM")
            && !Kondycja.czyWidocznyDlaCzlowieka("/System/Volumes/Preboot")
            && !Kondycja.czyWidocznyDlaCzlowieka("/Volumes/Recovery"))
sprawdz("kontrola ujemna — z --all hydrauliki jest WIĘCEJ niż bez",
        Kondycja.przeglad(wszystkie: true).count > przeglad.count)

// Ostrzeżenie o czymś, czego nie zmierzono, jest gorsze niż jego brak:
// uczy patrzącego ignorować ostrzeżenia. Dlatego `nil` jest tu odpowiedzią.
sprawdz("bez pojemności nie da się policzyć udziału wolnego",
        Kondycja.udzialWolnego(Kondycja.Wolumin(
            nazwa: "X", uuid: nil, punktMontowania: "/x", urzadzenie: nil,
            systemPlikow: nil, wewnetrzny: nil, sieciowy: false, wysuwalny: nil,
            szyfrowany: nil, zapisywalny: nil, startowy: nil,
            pojemnosc: nil, wolne: 100, wolneWKontenerze: nil, nosnik: nil)) == nil)
sprawdz("zero wolnego bez liczby z kontenera to „nie wiem\", nie „pełny\"",
        Kondycja.udzialWolnego(Kondycja.Wolumin(
            nazwa: "X", uuid: nil, punktMontowania: "/x", urzadzenie: nil,
            systemPlikow: nil, wewnetrzny: nil, sieciowy: false, wysuwalny: nil,
            szyfrowany: nil, zapisywalny: nil, startowy: nil,
            pojemnosc: 1000, wolne: 0, wolneWKontenerze: nil, nosnik: nil)) == nil)
sprawdz("kontrola dodatnia — realne liczby dają realny udział",
        Kondycja.udzialWolnego(Kondycja.Wolumin(
            nazwa: "X", uuid: nil, punktMontowania: "/x", urzadzenie: nil,
            systemPlikow: nil, wewnetrzny: nil, sieciowy: false, wysuwalny: nil,
            szyfrowany: nil, zapisywalny: nil, startowy: nil,
            pojemnosc: 1000, wolne: 50, wolneWKontenerze: nil, nosnik: nil)) == 0.05)

// CSV: nazwa woluminu może zawierać przecinek i cudzysłów — macOS na to pozwala.
sprawdz("przecinek w nazwie jest cytowany",
        Kondycja.cytuj("Backup, stary") == "\"Backup, stary\"")
sprawdz("cudzysłów w nazwie jest podwojony",
        Kondycja.cytuj("Dysk \"roboczy\"") == "\"Dysk \"\"roboczy\"\"\"")
sprawdz("zwykła nazwa NIE jest cytowana", Kondycja.cytuj("Mac Lab") == "Mac Lab")

let wiersze = Kondycja.csv(przeglad).split(separator: "\n")
sprawdz("CSV ma nagłówek plus wiersz na wolumin",
        wiersze.count == przeglad.count + 1)
sprawdz("nagłówek CSV ma tyle samo kolumn co każdy wiersz", {
    let kolumn = wiersze.first?.split(separator: ",", omittingEmptySubsequences: false).count
    // Liczymy tylko wiersze bez cytowania — te z przecinkiem w polu mają
    // inny podział i sprawdza je test cytowania wyżej.
    return wiersze.dropFirst().allSatisfy { w in
        w.contains("\"") || w.split(separator: ",", omittingEmptySubsequences: false).count == kolumn
    }
}())

print("\nAwarie: \(awarie), pominięte: \(pominiete)")
exit(awarie == 0 ? 0 : 1)
