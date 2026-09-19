# Change-Boot

Przełącznik systemu startowego dla macOS. Wybierasz, z której instalacji macOS ma
wystartować Mac, i klikasz raz — program sam sprawdza, czy firmware faktycznie
przyjął zmianę, i dopiero wtedy uruchamia maszynę ponownie.

Powstał pod konkretną potrzebę: drugi, czysty system na zewnętrznym dysku, do
testowania programów bez cudzych ustawień i do nagrywania materiałów.

## Co robi

- **Przełącza system startowy** i weryfikuje wynik. Gdy `bless` melduje sukces,
  a firmware nadal wskazuje stary dysk, restart **nie następuje** — inaczej Mac
  wystartowałby nie z tego systemu.
- **Czysty start**: programy i okna sprzed restartu nie wracają. Działa to na
  dwóch rzeczach naraz i obie są konieczne — ustawieniu `TALLogoutSavesState`
  oraz restarcie z parametrem `state saving preference`.
- **Wysuwa cały nośnik**, nie sam wolumin. Finder zostawia zamontowany ukryty
  wolumin danych i po wyciągnięciu wtyczki macOS zgłasza złe odmontowanie.
- **Pamięta systemy po UUID woluminu**, nie po nazwie. Zmiana nazwy dysku niczego
  nie psuje, a odpięty dysk zostaje na liście jako niedostępny.
- **Wiersz poleceń** — te same czynności ze skryptu albo z harmonogramu, z ustalonymi
  kodami wyjścia i wyjściem JSON. Samo `change-boot` otwiera widok pełnoekranowy
  obsługiwany strzałkami; każdy czasownik idzie zwykłym tekstem i ma nietknięte
  kody wyjścia.
- **Dziennik zdarzeń** — co, kiedy, przez kogo i z jakim skutkiem.
- Polski i angielski, do przełączenia w programie.

## Czego wymaga

| | |
|---|---|
| System | macOS 26 lub nowszy |
| Procesor | **Apple Silicon — sprawdzone.** Binarka jest uniwersalna i kod kompiluje się pod Intela, ale `bless`, T2 i Startup Security na prawdziwym Intelu **nie zostały sprawdzone** |
| Uprawnienia | administrator — raz przy instalacji pomocnika albo przy każdym przełączeniu, jeśli pomocnika nie zainstalujesz |
| Podpis | **lokalny certyfikat.** U obcego Gatekeeper poprosi o pierwsze wpuszczenie ręcznie |

> [!warning] Na Apple Silicon pierwsze pobłogosławienie woluminu może wymagać
> danych administratora — mówi to wprost `man bless`. Kolejne mogą iść same.
> Nie licz więc na w pełni bezobsługowe przełączanie za pierwszym razem.

## Co program zakłada poza sobą

To jest najważniejsza sekcja tego pliku. Change-Boot instaluje **trzy rzeczy poza
własnym pakietem** i żadnej z nich nie rusza Kosz:

| Co | Gdzie | Czyje | Kiedy powstaje |
|---|---|---|---|
| Pomocnik (demon) | launchd, domena systemowa | **root** | „Zainstaluj pomocnika" w Opcjach |
| `change-boot` | `/usr/local/bin` (dowiązanie) | `root:wheel` | „Zainstaluj polecenie" w Opcjach |
| Wpis logowania | Ustawienia → Obiekty logowania | użytkownika | autostart albo „otwórz po powrocie" |

Program **nie rusza** niczego poza tym. W szczególności nie dotyka ustawień systemu
innych niż `TALLogoutSavesState`, nie zagląda do prywatnych magazynów `loginwindow`
i nie wysyła niczego przez sieć — zero połączeń sieciowych, zero telemetrii,
zero raportowania awarii.

Ustawienia i dziennik zdarzeń leżą w:

```
~/Library/Preferences/com.mikagosz.ChangeBoot.plist
~/Library/Application Support/Change-Boot/
```

## Jak to odinstalować

🔴 **Zrób to, zanim przeciągniesz ikonę do Kosza.** Po skasowaniu programu zostaje
zarejestrowany demon roota wskazujący w pustkę i dowiązanie, którego nie skasujesz
bez hasła.

Z okna: **Opcje → Odinstalowanie Change-Boota → „Zdejmij wszystko, co zainstalowane"**.

Z terminala — działa także wtedy, gdy okna już nie otworzysz:

```bash
change-boot uninstall
```

Oba sposoby zdejmują pomocnika, polecenie i wpis logowania, a **ustawienia
i dziennik zostawiają nietknięte** — to twoje dane, nie śmieci po programie.
Skasujesz je ręcznie, jeśli chcesz; ścieżki są wypisywane po sprzątaniu.

Gdyby program zniknął, zanim posprzątałeś, zostaje droga ręczna:

```bash
sudo rm /usr/local/bin/change-boot
```

Demona zdejmuje się wtedy w Ustawieniach systemowych → Ogólne → Obiekty logowania,
w pozycji Change-Boota.

## Wiersz poleceń

```bash
change-boot                       # widok pełnoekranowy, do obsługi strzałkami
change-boot --plain               # to samo zwykłym tekstem
change-boot list                  # skonfigurowane systemy i ich dostępność
change-boot current               # gdzie jesteś i skąd wystartuje firmware
change-boot switch "Mac Lab" --restart
change-boot eject "Mac Lab"
change-boot log --limit 50 --json
change-boot uninstall
change-boot help
```

Kody wyjścia są **umową ze skryptami** i nie zmieniają znaczenia:

| Kod | Znaczy |
|---|---|
| 0 | zrobione |
| 1 | błąd |
| 2 | złe użycie |
| 3 | nie ma takiego woluminu |
| 4 | firmware nie przyjął celu — restartu nie było |
| 5 | anulowane przez użytkownika |

Polecenie instaluje się w Opcjach programu; bez niego działa pełna ścieżka do
binarki we wnętrzu pakietu.

## Budowanie i pakowanie

```bash
./spakuj.sh
```

🔴 **Nie pakuj przez zwykłe `xcodebuild … build`.** Produkt zależy od **akcji**,
nie od konfiguracji — oba polecenia mówią „Release" i dają co innego:

| | `build` | `archive` |
|---|---|---|
| architektura | tylko `arm64` | `x86_64 arm64` |
| uprawnienia | z `get-task-allow` | czyste |

`get-task-allow` pozwala podpiąć debugger do działającego programu. W programie,
który rozmawia z demonem roota, to jest droga do roota dla każdego procesu na
koncie użytkownika. `spakuj.sh` używa `archive` i sprawdza po fakcie pięć rzeczy:
architekturę, brak `get-task-allow`, obecność uprawnienia Apple Events, Hardened
Runtime i spójność podpisu. Paczka nie wychodzi, jeśli któraś kontrola padnie.

## Sprawdziany

Headless, przez `swiftc`, bez frameworków testowych i bez atrap — czytają prawdziwe
dyski tej maszyny, bo sprawdzane jest właśnie to, czy odczyt zgadza się
z rzeczywistością. Polecenie budowania każdego stoi w nagłówku jego `main.swift`.

```
Testy/wykrywanie     dyski, woluminy, odróżnianie Cryptexów od systemów
Testy/konfiguracja   lista, kolory, trwałość wpisu odpiętego dysku
Testy/pomocnik       kształt restartu, sito punktów montowania, zgodność podpisu
Testy/dziennik       zapis i odczyt, równoległość, rozbiór argumentów
```

Bez podłączonego dysku zewnętrznego część sprawdzianów jest **jawnie pomijana**,
nie zaliczana po cichu.

## Licencja

Jeszcze nieustalona. Do czasu wyboru program nie jest udostępniany na żadnej
licencji otwartej.
