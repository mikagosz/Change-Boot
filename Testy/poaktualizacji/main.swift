// Sprawdzian headless przypomnienia o ponownej instalacji pomocnika po aktualizacji.
//
//   cd "Xcode programy/Change-Boot"
//   swiftc -o /tmp/test-poaktualizacji Testy/poaktualizacji/main.swift \
//          Change-Boot/HelperAfterUpdateRule.swift && /tmp/test-poaktualizacji
//
// Reguła: przypomnienie tylko przy pierwszym starcie nowej wersji (ErrorUpdate
// `completedUpdate`) i tylko wtedy, gdy pomocnik był zarejestrowany.

import Foundation
import ServiceManagement

var ok = 0, zle = 0
func sprawdz(_ opis: String, _ warunek: Bool) {
    if warunek { ok += 1; print("  ✅ \(opis)") } else { zle += 1; print("  ❌ \(opis)") }
}

let r = HelperAfterUpdateRule.self
sprawdz("aktualizacja + pomocnik włączony → przypomnienie „0.2.23 → 0.2.24”",
        r.reminder(previousVersion: "0.2.23", currentVersion: "0.2.24", helperStatus: .enabled) == "0.2.23 → 0.2.24")
sprawdz("aktualizacja + pomocnik czeka na zgodę → przypomnienie",
        r.reminder(previousVersion: "0.2.23", currentVersion: "0.2.24", helperStatus: .requiresApproval) != nil)
sprawdz("aktualizacja + pomocnika nigdy nie było → cisza",
        r.reminder(previousVersion: "0.2.23", currentVersion: "0.2.24", helperStatus: .notRegistered) == nil)
sprawdz("aktualizacja + brak usługi w pakiecie → cisza",
        r.reminder(previousVersion: "0.2.23", currentVersion: "0.2.24", helperStatus: .notFound) == nil)
sprawdz("zwykłe uruchomienie (bez aktualizacji) → cisza",
        r.reminder(previousVersion: nil, currentVersion: nil, helperStatus: .enabled) == nil)

print(zle == 0 ? "\nWSZYSTKO OK (\(ok))" : "\nBŁĘDY: \(zle) (ok: \(ok))")
exit(zle == 0 ? 0 : 1)
