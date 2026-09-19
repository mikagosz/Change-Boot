# Change-Boot pod zarządzaniem MDM

Program dla jednej osoby przy jednym Macu konfiguruje się klikaniem. Pracownia
z czterdziestoma maszynami nie klika — dostaje profil konfiguracyjny i rozwozi go
serwerem MDM. Ten katalog opisuje, co profil może ustawić i czego się po nim
spodziewać.

## Klucze profilu

Domena: **`com.mikagosz.ChangeBoot`**. Wszystkie klucze są opcjonalne; profil
ustawia tylko to, czym chce rządzić, a reszta zostaje w rękach użytkownika.

| Klucz | Typ | Co robi |
|---|---|---|
| `AllowedVolumeUUIDs` | tablica napisów | Z tych woluminów wolno wystartować. Wszystko poza listą program odmawia, zanim cokolwiek zrobi — w oknie, w wierszu poleceń i w widoku pełnoekranowym |
| `RequireAdminForSwitch` | wartość logiczna | Przełączenie idzie przez systemowe okno hasła, nawet gdy pomocnik jest zainstalowany i gotów zrobić to bez pytania |
| `OrganizationName` | napis | Nazwa pokazywana w Opcjach przy zablokowanych przełącznikach |
| `cleanStartByDefault` | wartość logiczna | Czysty start jako wartość narzucona |
| `launchAfterSwitch` | wartość logiczna | Jednorazowy wpis logowania po powrocie |
| `launchAtLogin` | wartość logiczna | Program przy każdym zalogowaniu |
| `showsMenuBarIcon` | wartość logiczna | Ikona w pasku menu |
| `monochromeMenuBarIcon` | wartość logiczna | Ikona paska bez kolorów |
| `hidesDockIcon` | wartość logiczna | Zdejmowanie ikony z Docka |

Każdy klucz ustawiony profilem staje się w Opcjach **szary** i nie da się go
zmienić z maszyny. Program pokazuje wtedy u góry Opcji jedno zdanie z nazwą
organizacji, żeby szary przełącznik nie wyglądał na usterkę.

## Skąd wziąć UUID woluminów

Na maszynie wzorcowej, z zainstalowanym poleceniem terminalowym:

```bash
change-boot list --json
```

Pole `uuid` w każdym wierszu. To jest **UUID woluminu**, nie identyfikator
urządzenia (`disk3s3s1`) — ten drugi zmienia się przy przepięciu kabla, pierwszy
nie. Pole `dozwolony` w tym samym wyjściu pokazuje, jak program widzi wolumin
po nałożeniu profilu; skrypt sprawdzający flotę czyta właśnie je.

## Trzy rzeczy, o które warto zapytać, zanim się to rozwiezie

**Pusta tablica nie znaczy „nic nie wolno".** `AllowedVolumeUUIDs` z pustą
tablicą jest traktowane jak brak klucza, czyli brak ograniczenia. To jest
świadomy wybór: profil z pustą tablicą to prawie zawsze pozostałość po edycji,
a reguła „nie wolno nic" zamurowuje maszynę na tym systemie, z którego akurat
wystartowała — i nie ma jak jej cofnąć z tej maszyny.

**Reguła chodzi po UUID, nie po nazwie.** Nazwę dysku zmienia każdy w dwie
sekundy, więc reguła bezpieczeństwa oparta na nazwie nie jest regułą.

**Profil nie zastępuje pomocnika.** `RequireAdminForSwitch` mówi tylko, że
przełączenie ma kosztować świadomy gest. Bez tego klucza i z zainstalowanym
pomocnikiem przełączenie nie pyta o nic — i tak ma być na maszynie jednej osoby.

## Sprawdzenie, czy profil doszedł

```bash
sudo profiles show -type configuration | grep -A 5 ChangeBoot
defaults read /Library/Managed\ Preferences/com.mikagosz.ChangeBoot.plist
```

Pierwsze pyta system o zainstalowane profile, drugie pokazuje, co z nich
faktycznie wylądowało w domenie programu. Jeśli drugie polecenie mówi, że pliku
nie ma, profil **nie doszedł do tej domeny** — niezależnie od tego, co pokazuje
panel serwera MDM.

## Czego tu jeszcze nie ma

Paczka `.pkg` do rozwiezienia samego programu. Dziś instalacja to rozpakowanie
zipa i przeciągnięcie do Aplikacji, plus dwa kliknięcia w Opcjach (pomocnik,
polecenie terminalowe). Na jednej maszynie to minuta, na czterdziestu nie
przejdzie. Paczka jest następnym krokiem i ma zrobić całość bez ani jednego
kliknięcia.
