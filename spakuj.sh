#!/bin/zsh
# Jedyna droga pakowania Change-Boota do oddania komukolwiek.
#
# 🔴 Dlaczego skrypt, a nie zapamiętane polecenie. Audyt 2026-09-19 zmierzył, że
# produkt zależy od AKCJI xcodebuild, nie od konfiguracji:
#
#     xcodebuild … -configuration Release build     → arm64, z `get-task-allow`
#     xcodebuild … -configuration Release archive   → x86_64 arm64, bez uprawnień
#
# Oba polecenia mówią „Release" i dają co innego. Dlatego pakowanie ma jedną
# drogę, a na końcu trzy kontrole, które ją sprawdzają — nie pamięć człowieka.
#
# Użycie:  ./spakuj.sh            → zip ląduje w „My Code/App zip/Change-Boot/"
#
# 🔴 Zip idzie do App zip, a NIE do /tmp. Mike zbiera stamtąd paczki do instalacji
# i na dysk z kopiami; paczka zostawiona w /tmp wypada z tego obiegu, a do tego
# znika przy restarcie maszyny. Ścieżka jest względna wobec repozytorium, więc
# działa tak samo na MacBooku i na Mac mini — cały „My Code" jedzie synchronizacją.
#
# Kolejność ma znaczenie i jest jedna: kod → commit → build → zip. Zip zrobiony
# przed ostatnim commitem przestaje odpowiadać temu, co siedzi pod tagiem.

set -e
cd "${0:A:h}"

ARCHIWUM=/tmp/cb-pakowanie/Change-Boot.xcarchive
rm -rf /tmp/cb-pakowanie
mkdir -p /tmp/cb-pakowanie

echo "▸ Archiwizacja (to ona daje binarkę uniwersalną i czyste uprawnienia)"
xcodebuild -project Change-Boot.xcodeproj -scheme Change-Boot \
           -configuration Release -derivedDataPath /tmp/cb-pakowanie/dd \
           archive -archivePath "$ARCHIWUM" > /tmp/cb-pakowanie/build.log 2>&1 \
  || { echo "✗ Archiwizacja padła — log: /tmp/cb-pakowanie/build.log"; exit 1; }

APP="$ARCHIWUM/Products/Applications/Change-Boot.app"
WERSJA=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
CEL="/tmp/Change-Boot-$WERSJA"
rm -rf "$CEL"; mkdir -p "$CEL"
cp -R "$APP" "$CEL/"

echo "▸ Kontrole — każda musi przejść, inaczej paczka nie wychodzi"
BLEDY=0

ARCH=$(lipo -info "$CEL/Change-Boot.app/Contents/MacOS/Change-Boot")
if [[ "$ARCH" == *"x86_64"* && "$ARCH" == *"arm64"* ]]; then
  echo "  ✓ binarka uniwersalna (x86_64 arm64)"
else
  echo "  ✗ binarka NIE jest uniwersalna: $ARCH"; BLEDY=1
fi

UPR=$(codesign -d --entitlements - --xml "$CEL/Change-Boot.app" 2>/dev/null | plutil -p - 2>/dev/null)
if [[ "$UPR" == *"get-task-allow"* ]]; then
  echo "  ✗ paczka niesie get-task-allow — każdy proces użytkownika podepnie debugger"; BLEDY=1
else
  echo "  ✓ bez get-task-allow"
fi
if [[ "$UPR" == *"apple-events"* ]]; then
  echo "  ✓ uprawnienie apple-events obecne (bez niego restart i okno hasła mogą paść)"
else
  echo "  ✗ brak uprawnienia apple-events"; BLEDY=1
fi

if codesign -dv --verbose=2 "$CEL/Change-Boot.app" 2>&1 | grep -q "flags=.*runtime"; then
  echo "  ✓ Hardened Runtime włączony"
else
  echo "  ✗ Hardened Runtime WYŁĄCZONY"; BLEDY=1
fi

if codesign --verify --deep --strict "$CEL/Change-Boot.app" 2>/dev/null; then
  echo "  ✓ podpis spójny"
else
  echo "  ✗ podpis uszkodzony"; BLEDY=1
fi

if [[ $BLEDY -ne 0 ]]; then
  echo
  echo "❌ Paczka NIE nadaje się do oddania — popraw powyższe i uruchom ponownie."
  exit 1
fi

# ── zip do App zip ───────────────────────────────────────────────────────────
ZIPY="../../App zip/Change-Boot"
mkdir -p "$ZIPY"
ZIP="$ZIPY/Change-Boot $WERSJA.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$CEL/Change-Boot.app" "$ZIP"

# Kontrola przez rozpakowanie: `ditto` potrafi spakować bundle tak, że podpis
# nie przeżywa drogi powrotnej. Meldujemy gotowe dopiero po sprawdzeniu kopii,
# a nie po samym spakowaniu.
SPRAWDZ=$(mktemp -d)
ditto -x -k "$ZIP" "$SPRAWDZ"
if codesign --verify --deep --strict "$SPRAWDZ/Change-Boot.app" 2>/dev/null; then
  echo "  ✓ podpis przeżył spakowanie i rozpakowanie"
else
  echo "  ✗ po rozpakowaniu podpis jest uszkodzony"
  rm -rf "$SPRAWDZ"
  exit 1
fi
rm -rf "$SPRAWDZ"

echo
echo "✅ Change-Boot $WERSJA gotowy"
echo "   zip:      $(cd "$ZIPY" && pwd)/Change-Boot $WERSJA.zip"
echo "   rozpakowany do podmiany:  $CEL/Change-Boot.app"
echo "   Podpis lokalny — u obcego Gatekeeper poprosi o pierwsze wpuszczenie ręcznie."
