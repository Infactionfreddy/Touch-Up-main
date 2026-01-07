# ELAN Touchscreen Support

## Overview
Diese Version von Touch Up enthält erweiterte Unterstützung für ELAN Touchscreens. ELAN ist ein häufiger Hersteller von Touchscreen-Controllern, die in vielen Laptops und Monitoren verbaut sind.

## ELAN Vendor ID
- **Vendor ID**: 0x04F3
- ELAN-Geräte werden automatisch erkannt und mit speziellen Debug-Informationen protokolliert

## Implementierte Verbesserungen

### 1. Erweiterte Geräteerkennung
- Automatische Identifizierung von ELAN-Geräten anhand der Vendor ID
- Unterstützung für beide HID-Digitizer-Typen:
  - `kHIDUsage_Dig_TouchScreen` (Standard)
  - `kHIDUsage_Dig_Touch` (alternative ELAN-Implementierung)

### 2. Verbesserte Debug-Ausgabe
Bei der Verbindung eines ELAN-Touchscreens werden folgende Informationen protokolliert:
- Vendor ID und Product ID
- Produktname (falls verfügbar)
- ELAN-spezifische Identifikation
- HID-Element-Struktur mit Touch-Collection-Informationen

### 3. Laufzeit-Überwachung
- Automatische Benachrichtigung bei ELAN-Gerät-Verbindung/Trennung
- Detaillierte HID-Report-Analyse für ELAN-Geräte

## Fehlerbehebung

### Touchscreen wird nicht erkannt

1. **Überprüfen Sie die Systemprotokolle**:
   - Öffnen Sie Console.app (Programme > Dienstprogramme)
   - Filtern Sie nach "Touch" oder "ELAN"
   - Schließen Sie Ihren Touchscreen an
   - Suchen Sie nach Meldungen wie:
     ```
     Device detected - Vendor ID: 0x04F3, Product ID: 0x____
     ELAN Touchscreen detected!
     ```

2. **Überprüfen Sie die USB-Verbindung**:
   - Öffnen Sie die Systeminformationen (Apfel-Menü > Über diesen Mac > Systembericht)
   - Navigieren Sie zu "Hardware" > "USB"
   - Suchen Sie nach Ihrem ELAN-Gerät
   - Notieren Sie sich Vendor ID und Product ID

3. **Accessibility-Zugriff gewähren**:
   - Touch Up benötigt Zugriff auf die Bedienungshilfen-APIs
   - Gehen Sie zu Systemeinstellungen > Sicherheit & Datenschutz > Datenschutz > Bedienungshilfen
   - Stellen Sie sicher, dass Touch Up in der Liste aktiviert ist

4. **Sandbox-Berechtigungen prüfen**:
   - Touch Up benötigt USB-Zugriff
   - Dies ist in den Entitlements (Touch_Up.entitlements) konfiguriert

### Touch-Eingaben werden nicht verarbeitet

1. **Aktivieren Sie die Maus-Event-Veröffentlichung**:
   - Öffnen Sie die Touch Up Einstellungen
   - Aktivieren Sie "Enable Cursor" (oder ähnlich)

2. **Passen Sie die Fehlertoleranz an**:
   - In den Einstellungen unter "Troubleshooting"
   - Erhöhen Sie "Error Resistance" bei unzuverlässigen Touch-Reports

3. **Testen Sie im Debug-Modus**:
   - Klicken Sie auf "Open Fullscreen Test Environment"
   - Berühren Sie den Bildschirm und beobachten Sie die Touch-Points
   - Dies zeigt, ob die Touch-Daten korrekt empfangen werden

### Spezifische ELAN-Probleme

**Problem**: Touches werden an Position (0,0) gemeldet
- **Lösung**: Aktivieren Sie "Ignore touches at origin" in den Einstellungen

**Problem**: Touch-Eingaben sind verzögert oder springen
- **Lösung**: Passen Sie "Error Resistance" an (Standard: 0-2)
- Höhere Werte = mehr Stabilität, aber mehr Latenz

**Problem**: Multi-Touch funktioniert nicht korrekt
- **Überprüfung**: Console.app-Ausgabe zeigt die Anzahl der erkannten Touch-Collections
- ELAN-Geräte sollten mindestens 5-10 Touch-Points unterstützen

## Technische Details

### HID-Report-Struktur
ELAN Touchscreens verwenden typischerweise folgende HID-Elemente:
- **Page**: Digitizer (0x0D)
- **Usage**: TouchScreen (0x04) oder Touch (0x22)
- **Logical Collections**: Eine pro Touch-Point
- **Elemente pro Touch**:
  - X/Y Position (Generic Desktop Page)
  - Contact Identifier (Digitizer Page)
  - Tip Switch (Digitizer Page)
  - Touch Valid/Confidence (Digitizer Page)
  - Optional: Width, Height, Azimuth

### Hybrid-Modus
Einige ELAN-Geräte mit mehr als 10 Touch-Points verwenden einen Hybrid-Modus:
- Touch-Daten werden in mehreren Batches gesendet
- Touch Up erkennt und handhabt dies automatisch
- Erkennbar an ContactCount = 0 nach dem ersten Batch

## Bekannte kompatible ELAN-Geräte

Folgende ELAN-Geräte wurden erfolgreich getestet:
- _(Fügen Sie hier Ihre Gerätemodelle hinzu)_

Um Ihr Gerät zur Liste hinzuzufügen, öffnen Sie bitte ein Issue auf GitHub mit:
- Gerätemodell und Hersteller
- Product ID (aus Systeminformationen oder Console.app)
- Anzahl der unterstützten Touch-Points

## Entwickler-Hinweise

### Code-Änderungen für ELAN-Support

1. **HIDInterpreter.c**:
   - `kELANVendorID` Konstante (0x04F3)
   - `gIsELANDevice` Flag für Laufzeit-Erkennung
   - Erweiterte Device-Matching in `OpenHIDManager()`
   - Vendor/Product ID Logging in `Handle_DeviceMatchingCallback()`

2. **SettingsView.swift**:
   - ELAN-Informationen im Troubleshooting-Bereich
   - Hinweis zur Console.app-Überprüfung

### Weitere Anpassungen

Wenn Ihr ELAN-Gerät spezielle Behandlung benötigt:

1. Identifizieren Sie die spezifischen HID-Report-Eigenschaften
2. Fügen Sie gerätespezifische Quirks in `HIDInterpreter.c` hinzu
3. Verwenden Sie `gIsELANDevice` Flag für bedingte Logik
4. Testen Sie mit aktiviertem Debug-Output (`IdentifyElements()` mit `TRUE`)

## Support und Beiträge

Wenn Sie Probleme mit einem ELAN-Touchscreen haben:

1. Sammeln Sie Debug-Informationen:
   - Console.app Logs
   - Systeminformationen (USB-Geräte)
   - Touch Up Debug-Overlay-Screenshots

2. Öffnen Sie ein Issue auf GitHub:
   - https://github.com/shueber/Touch-Up/issues
   - Verwenden Sie das Label "ELAN Support"
   - Fügen Sie alle Debug-Informationen bei

3. Erwägen Sie einen Pull Request:
   - Gerätespezifische Fixes
   - Neue ELAN-Geräte-IDs
   - Verbesserte Dokumentation

## Lizenz

Diese ELAN-Support-Erweiterung steht unter der gleichen MIT-Lizenz wie das Hauptprojekt.
