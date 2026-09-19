import AppKit
import SwiftUI

/// Ikona w pasku menu: dwa dyski jeden na drugim, z przesunięciem.
///
/// Kolory pochodzą z ikony programu — zmierzone z `finalico.png` w polu pod każdym
/// z dwóch dysków: zieleń pod wypełnionym, fiolet pod konturowym.
///
/// 🔴 Rysowane jako `NSImage` z `isTemplate = false`, a NIE jako `Image(systemName:)`.
/// Pasek menu traktuje ikonę SwiftUI jak **szablon**: bierze z niej sam kształt
/// i maluje go jedną barwą systemową. Zmierzone 2026-09-19 — oba dyski wyszły białe
/// i zlały się w jedną plamę. Tylko obraz oznaczony jako nie-szablon zachowuje barwy.
enum MenuBarIcon {

    static let zielen = NSColor(srgbRed: 0x7C/255, green: 0xDA/255, blue: 0xB2/255, alpha: 1)
    static let fiolet = NSColor(srgbRed: 0x89/255, green: 0x80/255, blue: 0xDC/255, alpha: 1)

    /// Wysokość pozycji paska menu. Powyżej ~18 pt macOS zaczyna przycinać.
    private static let wysokosc: CGFloat = 18
    private static let szerokosc: CGFloat = 22

    /// Bok pojedynczego dysku i przesunięcie między nimi.
    ///
    /// Dyski mają na siebie **zachodzić**, a nie stać obok — przesunięcie jest
    /// mniejsze niż połowa dysku, więc nakładają się w jakichś 60%.
    private static let dyskW: CGFloat = 16
    private static let dyskH: CGFloat = 13
    private static let przesuniecieX: CGFloat = 6
    private static let przesuniecieY: CGFloat = 5

    /// Obie wersje liczone raz i trzymane: pasek menu odpytuje etykietę często,
    /// a rysowanie symboli z obrysem nie jest darmowe.
    static let obraz: NSImage = zbuduj()
    static let obrazMono: NSImage = zbudujMono()

    static func obraz(monochromatyczna: Bool) -> NSImage {
        monochromatyczna ? obrazMono : obraz
    }

    /// Wariant bez kolorów: te same **dwa** dyski, rysowane jako szablon.
    ///
    /// `isTemplate = true` oddaje barwienie systemowi — ikona sama trzyma się
    /// trybu jasnego i ciemnego, podświetlenia po kliknięciu i ograniczonej
    /// przezroczystości. Dokładnie to, czego wersja kolorowa zrobić nie może.
    ///
    /// 🔴 Do 0.1.15 stał tu **jeden** dysk, z uzasadnieniem, że w szablonie nie ma
    /// jak rozdzielić zachodzących kształtów obrysem w kolorze tła — tło jest
    /// wtedy nieznane, bo maluje je system. To prawda o obrysie, ale nie o całym
    /// problemie: szparę da się **wyciąć**, a nie zamalować. Wersja kolorowa kładzie
    /// pod przednim dyskiem cztery przesunięte kopie w kolorze tła; tutaj te same
    /// kopie idą operacją `destinationOut`, czyli zjadają alfę tylnego dysku.
    /// Szpara wychodzi przezroczysta, więc pokazuje pasek menu — a to jest
    /// rozdzielenie działające na każdym tle, także na tym, którego nie znamy.
    ///
    /// Zgłoszone przez [U] 2026-09-19: *„po przełączeniu na monochromatyczną widnieje
    /// ikona tylko jednego dysku zamiast dwóch"*. Obie wersje mają pokazywać to samo,
    /// bo obie są tym samym programem.
    private static func zbudujMono() -> NSImage {
        let rozmiar = NSSize(width: szerokosc, height: wysokosc)
        let img = NSImage(size: rozmiar, flipped: false) { _ in
            guard let tyl = sylwetka("internaldrive.fill"),
                  let przod = sylwetka("externaldrive.fill") else { return true }

            let ramkaTyl = NSRect(x: przesuniecieX, y: przesuniecieY,
                                  width: dyskW, height: dyskH)
            let ramkaPrzodu = NSRect(x: 0, y: 0, width: dyskW, height: dyskH)

            tyl.draw(in: ramkaTyl, from: .zero, operation: .sourceOver, fraction: 1)

            // Szpara: przedni dysk rozdmuchany o 0,9 pt na wszystkie strony,
            // wycięty z tego, co już leży. Te same 0,9 pt co w wersji kolorowej,
            // żeby obie ikony miały identyczną grubość rozdzielenia.
            for dx in [-0.9, 0, 0.9] as [CGFloat] {
                for dy in [-0.9, 0, 0.9] as [CGFloat] {
                    przod.draw(in: ramkaPrzodu.offsetBy(dx: dx, dy: dy),
                               from: .zero, operation: .destinationOut, fraction: 1)
                }
            }

            przod.draw(in: ramkaPrzodu, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Symbol jako pełna czarna sylwetka.
    ///
    /// Rysowany wprost symbol SF nie ma obiecanego koloru — zależy on od ustawień
    /// kontekstu i konfiguracji symbolu. W szablonie liczy się wyłącznie kanał alfa,
    /// więc kształt wycinamy z czarnego prostokąta przez `destinationIn` i mamy
    /// pewność, co dalej wchodzi do operacji `destinationOut`.
    private static func sylwetka(_ symbol: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        guard let symbolImg = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) else { return nil }
        return NSImage(size: symbolImg.size, flipped: false) { rect in
            NSColor.black.set()
            rect.fill()
            symbolImg.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
    }

    private static func zbuduj() -> NSImage {
        let rozmiar = NSSize(width: szerokosc, height: wysokosc)
        let img = NSImage(size: rozmiar, flipped: false) { _ in
            // Dysk wewnętrzny z tyłu, po prawej u góry; zewnętrzny na wierzchu,
            // po lewej u dołu — ten sam układ co na ikonie programu.
            narysuj("internaldrive.fill", kolor: zielen,
                    w: NSRect(x: przesuniecieX, y: przesuniecieY, width: dyskW, height: dyskH))
            narysuj("externaldrive.fill", kolor: fiolet,
                    w: NSRect(x: 0, y: 0, width: dyskW, height: dyskH))
            return true
        }
        // Bez tego pasek menu przemaluje wszystko na jeden kolor.
        img.isTemplate = false
        return img
    }

    private static func narysuj(_ symbol: String, kolor: NSColor, w ramka: NSRect) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        guard let symbolImg = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) else { return }

        // Obrys w kolorze tła rozdziela oba dyski, gdy na siebie zachodzą.
        let obrys = NSImage(size: symbolImg.size, flipped: false) { rect in
            NSColor.black.set()
            rect.fill()
            symbolImg.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        for dx in [-0.9, 0.9] as [CGFloat] {
            for dy in [-0.9, 0.9] as [CGFloat] {
                obrys.draw(in: ramka.offsetBy(dx: dx, dy: dy),
                           from: .zero, operation: .sourceOver, fraction: 0.85)
            }
        }

        let pokolorowany = NSImage(size: symbolImg.size, flipped: false) { rect in
            kolor.set()
            rect.fill()
            symbolImg.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        pokolorowany.draw(in: ramka, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

struct MenuBarIconView: View {
    let monochromatyczna: Bool

    var body: some View {
        // `.original` tylko dla wersji kolorowej. Szablon ma zostać szablonem,
        // inaczej system nie przemaluje go pod tryb jasny i podświetlenie.
        Image(nsImage: MenuBarIcon.obraz(monochromatyczna: monochromatyczna))
            .renderingMode(monochromatyczna ? .template : .original)
            .accessibilityLabel(Text("Change-Boot"))
    }
}
