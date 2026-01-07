# Touch Up - Projekt-Struktur

## ✅ Aktive Kern-Komponenten

### TouchUpCore/ (Objective-C/C Framework)
**Status**: ✅ KRITISCH - Hauptlogik

#### HIDInterpreter.c/h
- **Funktion**: Kommunikation mit HID-Geräten (IOKit)
- **Wichtig**: 
  - Device-Matching für ELAN Touchscreens (Vendor 0x0712)
  - HID Queue Setup und Event-Processing
  - 10 Touch-Collections für Multi-Touch
  - Feature Reports für Device-Initialisierung

#### TUCTouchInputManager.m/h
- **Funktion**: Touch-Event-Verarbeitung und Cursor-Steuerung
- **Wichtig**:
  - Touch-Phase-Management (BEGAN, MOVED, ENDED, CANCELLED)
  - Cursor-Zuordnung (`cursorTouch`)
  - Mouse-Event-Generierung
  - Tap vs. Drag Erkennung
  - Touch-Timeout-Handling (`errorResistance`)

#### TUCTouch.m/h
- **Funktion**: Touch-Objekt (einzelner Berührungspunkt)
- **Eigenschaften**: contactID, position, phase, lastUpdated

#### TUCCursorUtilities.m/h
- **Funktion**: Cursor-Bewegung per CGEvent API
- **Wichtig**: `moveCursorTo()` für absolute Positionierung

#### TUCScreen.m/h
- **Funktion**: Screen-Koordinaten-Konvertierung
- **Wichtig**: Relative Touch-Koordinaten → Absolute Screen-Koordinaten

### Touch Up/ (Swift UI)

#### AppDelegate.swift
- **Funktion**: App-Lifecycle, Menu-Bar-Item
- **Wichtig**: 
  - Accessibility-Berechtigungsprüfung
  - TouchManager Start/Stop
  - Status-Menu-Integration

#### TouchUp.swift
- **Funktion**: SwiftUI Model (ObservableObject)
- **Verbindet**: UI ↔ TouchUpCore Framework

#### SettingsView.swift
- **Funktion**: Einstellungs-UI
- **Features**: Screen-Auswahl, Aktivierung

#### DebugView.swift
- **Funktion**: Touch-Overlay für Debugging
- **Features**: Visualisierung aller Touch-Points

### Touch Up.xcodeproj/
- **Xcode-Projekt-Dateien**
- **Build-Settings**: Code-Signing, Entitlements

## 📦 Build-Artefakte

### build/Debug/
- **Aktuelle Build-Outputs**
- **Touch Up.app** - Lauffähige Anwendung

### build/ExplicitPrecompiledModules/
- **Swift/Objective-C Module Cache**

## 🗄️ Archivierte Komponenten

### _Archive/unused_code/
- **USBDirectAccessor.c/h** - Nicht verwendet (HID funktioniert direkt)
- **Touch_Up_Extension/** - Leer, nie implementiert

### _Archive/old_builds/
- **Debug 2/** - Alte Build-Artefakte

## 📝 Dokumentation

- **BUILD_GUIDE_DE.md** - Deutsche Build-Anleitung
- **ELAN_SUPPORT.md** - ELAN-Touchscreen-Spezifikationen
- **CHANGELOG_ELAN.md** - Änderungshistorie
- **README.md** - Projekt-Übersicht

## 🔑 Wichtige Konfigurationsdateien

### Touch_Up.entitlements
- **Berechtigungen**:
  - `com.apple.security.device.hid` ✅ KRITISCH für HID-Zugriff
  - `com.apple.security.accessibility` ✅ KRITISCH für Mouse-Events
  - `com.apple.security.device.usb` (Fallback)

### de.schafe.Touch-Up.plist
- **LaunchAgent-Konfiguration** (optional)

## 🎯 Aktuelle Funktionalität (Stand: 04.01.2026)

✅ **Funktioniert**:
- ELAN Touchscreen-Erkennung (Vendor 0x0712)
- Single Tap mit Cursor-Bewegung
- Multi-Tap (mehrere Taps nacheinander)
- Drag (Ziehen mit Cursor-Bewegung)
- Multi-Touch-Erkennung (10 simultane Touches)
- Touch-Overlay zur Visualisierung

✅ **Gelöste Probleme**:
- TCC-Berechtigung für HID-Zugriff
- cursorTouch-Reset nach ENDED
- Empty Touch Slot Filterung
- Touch-Timeout-Mechanismus

## 🚀 Kompilierung

```bash
cd "/Users/frede/Documents/Programming/Touch-Up-main"
xcodebuild build -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# Ad-hoc Signierung für Entitlements
xattr -rc build/Debug/"Touch Up.app"
codesign --force --deep --sign - build/Debug/"Touch Up.app"

# Starten
open build/Debug/"Touch Up.app"
```

## 🧹 Wartung

- **Regel**: Nicht verwendeter Code → `_Archive/unused_code/`
- **Regel**: Alte Builds → `_Archive/old_builds/`
- **Regel**: Debug-Logs können reduziert werden, wenn stabil
