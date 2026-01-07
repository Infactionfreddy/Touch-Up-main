# Build-Anleitung für Touch Up mit ELAN-Support

## Voraussetzungen

- macOS 11.0 oder höher
- Xcode 13.0 oder höher
- Ein angeschlossener ELAN Touchscreen zum Testen (optional)

## Schritte

### 1. Projekt öffnen

```bash
cd /Users/frede/Documents/Programming/Touch-Up-main
open "Touch Up.xcodeproj"
```

### 2. In Xcode

1. Wählen Sie das "Touch Up"-Schema aus
2. Wählen Sie "My Mac" als Ziel
3. Prüfen Sie die Signing-Einstellungen unter "Signing & Capabilities"

### 3. Entitlements prüfen

Die Datei `Touch Up/Touch_Up.entitlements` sollte folgende Berechtigungen enthalten:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.usb</key>
    <true/>
</dict>
</plist>
```

### 4. Kompilieren und Ausführen

**Debug-Build**:
- Drücken Sie `Cmd + R` oder klicken Sie auf den "Run"-Button
- Dies startet die App im Debug-Modus mit Console-Ausgabe

**Release-Build**:
```bash
xcodebuild -project "Touch Up.xcodeproj" \
  -scheme "Touch Up" \
  -configuration Release \
  -derivedDataPath build \
  build
```

Die kompilierte App befindet sich dann in:
```
build/Build/Products/Release/Touch Up.app
```

### 5. ELAN-Touchscreen testen

1. **Starten Sie die App**
2. **Öffnen Sie Console.app** (Programme > Dienstprogramme)
3. **Filter setzen**: Geben Sie "Touch" oder "ELAN" in das Suchfeld ein
4. **Touchscreen anschließen**
5. **Überprüfen Sie die Ausgabe**:
   ```
   Initializing HID Manager with ELAN touchscreen support...
   ELAN Vendor ID: 0x04F3
   Device detected - Vendor ID: 0x04F3, Product ID: 0x____
   Product Name: ELAN Touchscreen (oder ähnlich)
   ELAN Touchscreen detected!
   === ELAN Device Element Structure ===
   ...
   === ELAN Device: Found X touch collection elements ===
   ```

6. **Testen Sie Touch-Eingaben**:
   - Öffnen Sie die Touch Up Einstellungen
   - Klicken Sie auf "Open Fullscreen Test Environment"
   - Berühren Sie den Bildschirm und beobachten Sie die visualisierten Touch-Points

## Fehlerbehebung beim Build

### Problem: Code Signing-Fehler

**Symptom**: "Code signing is required"

**Lösung**:
1. Gehen Sie zu Projekt-Einstellungen > Signing & Capabilities
2. Aktivieren Sie "Automatically manage signing"
3. Wählen Sie Ihr Team aus
4. Oder deaktivieren Sie Code Signing für Debug-Builds (nicht empfohlen)

### Problem: USB-Berechtigung fehlt

**Symptom**: Touchscreen wird nicht erkannt, keine Console-Ausgabe

**Lösung**:
Prüfen Sie `Touch_Up.entitlements`:
- Stellen Sie sicher, dass `com.apple.security.device.usb` auf `true` gesetzt ist

### Problem: Accessibility-Zugriff

**Symptom**: App läuft, aber Touch-Eingaben bewegen den Cursor nicht

**Lösung**:
1. Systemeinstellungen > Sicherheit & Datenschutz > Datenschutz > Bedienungshilfen
2. Klicken Sie auf das Schloss-Symbol und authentifizieren Sie sich
3. Fügen Sie "Touch Up" hinzu oder aktivieren Sie es

### Problem: "Framework not found TouchUpCore"

**Symptom**: Build-Fehler beim Kompilieren

**Lösung**:
1. Prüfen Sie, ob alle TouchUpCore-Dateien im Projekt enthalten sind
2. Projekt > Build Settings > Framework Search Paths überprüfen
3. Clean Build Folder: `Shift + Cmd + K`, dann neu kompilieren

## Installation der kompilierten App

### Lokale Installation

Kopieren Sie die kompilierte App nach `/Applications`:
```bash
cp -R "build/Build/Products/Release/Touch Up.app" /Applications/
```

### Login Item hinzufügen

1. Systemeinstellungen > Benutzer & Gruppen
2. Ihr Benutzerkonto auswählen
3. Anmeldeobjekte
4. `+` klicken und "Touch Up" auswählen

## Notarisierung (für Verteilung)

Wenn Sie die App verteilen möchten:

1. **Developer ID Certificate** benötigt
2. **Notarisierung** bei Apple:

```bash
# App archivieren
xcodebuild archive \
  -project "Touch Up.xcodeproj" \
  -scheme "Touch Up" \
  -configuration Release \
  -archivePath "TouchUp.xcarchive"

# Exportieren
xcodebuild -exportArchive \
  -archivePath "TouchUp.xcarchive" \
  -exportPath "TouchUp-Export" \
  -exportOptionsPlist ExportOptions.plist

# Notarisieren (benötigt Apple ID)
xcrun notarytool submit "TouchUp-Export/Touch Up.app" \
  --apple-id "your@email.com" \
  --password "app-specific-password" \
  --team-id "TEAM_ID"
```

## Entwickler-Modus für ELAN-Debugging

Für intensive ELAN-Debugging-Arbeit:

### Erweiterte Console-Ausgabe aktivieren

In `HIDInterpreter.c`, aktivieren Sie zusätzliches Logging:

```c
// In DispatchTouchDataForCollection() - vor dem Return:
if (gIsELANDevice) {
    printf("ELAN Touch: ID=%ld, X=%.2f, Y=%.2f, Tip=%ld\\n", 
           contactID, x, y, tipSwitch);
}
```

### Alle HID-Values loggen

In `Handle_QueueValueAvailable()`:

```c
StoreInputValue(valueRef);

if (gIsELANDevice) {
    PrintInput(valueRef);  // Aktivieren Sie diese Zeile
}
```

**Warnung**: Dies erzeugt sehr viel Console-Ausgabe!

## Performance-Optimierungen

### Für ELAN-Geräte mit hoher Report-Rate

Wenn Ihr ELAN-Touchscreen eine sehr hohe Report-Rate hat (>120Hz):

1. Erwägen Sie Thread-Priority-Anpassungen in `TUCTouchInputManager.m`
2. Optimieren Sie `errorResistance` in den Einstellungen
3. Testen Sie verschiedene `holdDuration`-Werte

## Nächste Schritte

Nach erfolgreichem Build und Test:

1. **Erstellen Sie einen Issue/PR auf GitHub** mit Ihren ELAN-Gerätedetails
2. **Teilen Sie Ihre Erfahrungen** in der Community
3. **Dokumentieren Sie spezifische Quirks** für Ihr Gerät
4. **Testen Sie verschiedene Anwendungen** (Safari, Finder, etc.)

## Weitere Ressourcen

- Apple HID Documentation: https://developer.apple.com/documentation/iokit/hid
- USB-IF HID Usage Tables: https://usb.org/hid
- Accessibility API: https://developer.apple.com/accessibility/

## Support

Bei Fragen zum Build-Prozess:
- GitHub Issues: https://github.com/shueber/Touch-Up/issues
- Tag: `build`, `elan-support`
