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

    static let obraz: NSImage = zbuduj()

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
    var body: some View {
        Image(nsImage: MenuBarIcon.obraz)
            .renderingMode(.original)
            .accessibilityLabel(Text("Change-Boot"))
    }
}
