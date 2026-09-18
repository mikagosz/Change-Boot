// Sprawdzian headless wykrywania systemów i łańcucha dysków.
//
//   cd "Xcode programy/Change-Boot"
//   swiftc -o /tmp/test-wykrywanie Testy/wykrywanie/main.swift \
//          Change-Boot/DiskUtility.swift Change-Boot/BootSystem.swift && /tmp/test-wykrywanie
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

print("\nAwarie: \(awarie), pominięte: \(pominiete)")
exit(awarie == 0 ? 0 : 1)
