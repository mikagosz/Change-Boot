import Foundation

/// Surowa warstwa terminala: tryb bez echa, osobny ekran, odczyt klawiszy.
///
/// Wszystko własne, zgodnie z konwencją projektu — Apple SDK plus własny kod.
/// Zero bibliotek zewnętrznych.
enum Terminal {

    // MARK: - Przywracanie

    /// Ustawienia terminala z chwili wejścia w tryb surowy.
    private static var zapamietane: termios?
    private static var zapiete = false

    /// 🔴 **Najważniejsza rzecz w tym pliku.**
    ///
    /// Program, który wejdzie w tryb surowy i zginie bez przywrócenia ustawień,
    /// zostawia człowieka w powłoce **bez echa i bez działającego Ctrl-C** —
    /// wpisywane znaki nie pokazują się, a Enter nic nie robi. Naprawia to dopiero
    /// `reset` wpisany na ślepo.
    ///
    /// Dlatego przywracanie wisi na **wszystkich** drogach wyjścia naraz:
    /// normalnym końcu (`atexit`), przerwaniu (`SIGINT`), zakończeniu (`SIGTERM`)
    /// i zerwaniu połączenia (`SIGHUP`). Jedna droga to za mało — akurat ta
    /// nieobsłużona zawsze okaże się tą, którą człowiek wyjdzie.
    ///
    /// Obsługa sygnału idzie przez `sigaction`, a nie `DispatchSourceSignal`:
    /// źródło GCD wymaga działającej kolejki, a my jesteśmy w pętli czytającej
    /// z wejścia i na kolejkę nikt nie zagląda.
    private static func zapnijPrzywracanie() {
        guard !zapiete else { return }
        zapiete = true

        atexit { Terminal.przywroc() }

        for sygnal in [SIGINT, SIGTERM, SIGHUP] {
            var akcja = sigaction()
            akcja.__sigaction_u.__sa_handler = { _ in
                Terminal.przywroc()
                // Kończymy kodem umownym dla „zabity sygnałem", zamiast wracać
                // do pętli — po przywróceniu terminala nie ma po co wracać.
                _exit(130)
            }
            sigemptyset(&akcja.sa_mask)
            akcja.sa_flags = 0
            sigaction(sygnal, &akcja, nil)
        }
    }

    /// Przywraca terminal do stanu sprzed. Wolno wołać wielokrotnie.
    static func przywroc() {
        guard var stare = zapamietane else { return }
        zapamietane = nil
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &stare)
        pisz(pokazKursor + zwyklyEkran)
    }

    // MARK: - Tryb surowy

    /// Czy program rozmawia z człowiekiem przy klawiaturze.
    ///
    /// Sprawdzane są **oba** deskryptory: wyjście przekierowane do pliku znaczy,
    /// że nikt tego nie ogląda, a wejście z potoku — że nikt nie naciśnie klawisza.
    static var czyTerminal: Bool {
        isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    }

    /// Czy w tym terminalu wolno malować kolorem.
    ///
    /// `NO_COLOR` to umowa międzyprogramowa — jeśli ktoś ją ustawił, to znaczy,
    /// że ma powód. `TERM=dumb` mówi to samo o samym terminalu.
    static var czyKolor: Bool {
        let srodowisko = ProcessInfo.processInfo.environment
        if srodowisko["NO_COLOR"] != nil { return false }
        if (srodowisko["TERM"] ?? "") == "dumb" { return false }
        return true
    }

    /// Czy terminal zgłasza kolor 24-bitowy.
    ///
    /// 🔴 Zmierzone 2026-09-19: Terminal.app 2.15 **nie zgłasza RGB** w terminfo
    /// (`infocmp -x xterm-256color` → `colors#256`, zero trafień na `RGB`).
    /// Dlatego paleta musi umieć zejść na 256 kolorów, a nie zakładać dokładnych barw.
    static var czyPelnyKolor: Bool {
        let ct = ProcessInfo.processInfo.environment["COLORTERM"] ?? ""
        return ct.contains("truecolor") || ct.contains("24bit")
    }

    @discardableResult
    static func wejdzWTrybSurowy() -> Bool {
        guard czyTerminal, zapamietane == nil else { return false }

        var stare = termios()
        guard tcgetattr(STDIN_FILENO, &stare) == 0 else { return false }
        zapamietane = stare
        zapnijPrzywracanie()

        var nowe = stare
        // Zdejmujemy wyłącznie echo i tryb liniowy. `cfmakeraw` zabrałoby też
        // tłumaczenie znaku końca linii na wyjściu, przez co każdy `print`
        // schodziłby o wiersz, ale nie wracał na lewy margines.
        nowe.c_lflag &= ~tcflag_t(ECHO | ICANON)
        // Czytamy po jednym bajcie, bez czekania na więcej.
        withUnsafeMutableBytes(of: &nowe.c_cc) { bufor in
            bufor[Int(VMIN)] = 1
            bufor[Int(VTIME)] = 0
        }
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &nowe) == 0 else {
            zapamietane = nil
            return false
        }
        pisz(osobnyEkran + schowajKursor)
        return true
    }

    // MARK: - Sekwencje sterujące

    static let osobnyEkran = "\u{1B}[?1049h"
    static let zwyklyEkran = "\u{1B}[?1049l"
    static let schowajKursor = "\u{1B}[?25l"
    static let pokazKursor = "\u{1B}[?25h"
    static let wyczysc = "\u{1B}[2J\u{1B}[H"
    static let naPoczatek = "\u{1B}[H"

    static func pisz(_ tekst: String) {
        FileHandle.standardOutput.write(Data(tekst.utf8))
    }

    // MARK: - Rozmiar okna

    struct Rozmiar { let kolumny: Int, wiersze: Int }

    /// Rozmiar okna terminala. Przy nieznanym zwraca 80×24 — najstarszą
    /// bezpieczną wartość, przy której nic się nie rozjedzie.
    static var rozmiar: Rozmiar {
        var w = winsize()
        guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &w) == 0,
              w.ws_col > 0, w.ws_row > 0 else { return Rozmiar(kolumny: 80, wiersze: 24) }
        return Rozmiar(kolumny: Int(w.ws_col), wiersze: Int(w.ws_row))
    }

    // MARK: - Klawisze

    enum Klawisz: Equatable {
        case gora, dol, enter, escape
        case znak(Character)
        case inne
    }

    /// Czyta jeden klawisz. Blokuje do naciśnięcia.
    ///
    /// Strzałki przychodzą jako trzy bajty: `ESC` `[` `A`…`D`. Samo `ESC` też
    /// jest klawiszem, więc po nim czytamy **nieblokująco** — inaczej wciśnięcie
    /// Escape zawieszałoby program do następnego klawisza.
    static func czytajKlawisz() -> Klawisz {
        guard let pierwszy = bajt() else { return .inne }
        switch pierwszy {
        case 0x0A, 0x0D: return .enter
        case 0x03:       return .znak("q")          // Ctrl-C traktujemy jak wyjście
        case 0x1B:
            guard let drugi = bajtNieblokujaco(), drugi == 0x5B,
                  let trzeci = bajtNieblokujaco() else { return .escape }
            switch trzeci {
            case 0x41: return .gora
            case 0x42: return .dol
            default:   return .inne
            }
        default:
            guard let skalar = Unicode.Scalar(UInt32(pierwszy)) else { return .inne }
            return .znak(Character(skalar))
        }
    }

    private static func bajt() -> UInt8? {
        var b: UInt8 = 0
        return read(STDIN_FILENO, &b, 1) == 1 ? b : nil
    }

    /// Odczyt z krótkim terminem — do rozpoznawania sekwencji strzałek.
    private static func bajtNieblokujaco() -> UInt8? {
        var zestaw = fd_set()
        fdZeruj(&zestaw)
        fdUstaw(STDIN_FILENO, &zestaw)
        var termin = timeval(tv_sec: 0, tv_usec: 50_000)   // 50 ms
        guard select(STDIN_FILENO + 1, &zestaw, nil, nil, &termin) > 0 else { return nil }
        return bajt()
    }

    // `FD_ZERO` i `FD_SET` to makra C — w Swifcie trzeba je napisać samemu.
    private static func fdZeruj(_ zestaw: inout fd_set) {
        _ = withUnsafeMutableBytes(of: &zestaw.fds_bits) { bufor in
            bufor.initializeMemory(as: Int32.self, repeating: 0)
        }
    }
    private static func fdUstaw(_ fd: Int32, _ zestaw: inout fd_set) {
        let indeks = Int(fd) / 32, bit = Int32(1) << (Int32(fd) % 32)
        withUnsafeMutableBytes(of: &zestaw.fds_bits) { bufor in
            let slowa = bufor.bindMemory(to: Int32.self)
            slowa[indeks] |= bit
        }
    }
}
