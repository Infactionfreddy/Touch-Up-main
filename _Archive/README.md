# Archive - Nicht verwendete Touch Up Komponenten

Dieser Ordner enthält Code und Build-Artefakte, die nicht mehr aktiv verwendet werden.

## unused_code/

### USBDirectAccessor.c/h
- **Status**: Deaktiviert (auskommentiert in HIDInterpreter.c)
- **Grund**: Nicht benötigt - HID-Manager funktioniert direkt mit ELAN-Geräten
- **Ursprüngliche Funktion**: Direkter USB-Zugriff als Fallback für Geräte, die nicht über HID erkannt wurden
- **Hinweis**: Kann reaktiviert werden, falls HID-Zugriff bei einem Gerät fehlschlägt

### Touch_Up_Extension/
- **Status**: Komplett leer
- **Grund**: Wurde nie implementiert/verwendet
- **Kann gelöscht werden**: Ja

## old_builds/

### Debug 2/
- **Status**: Alte Build-Artefakte
- **Grund**: Duplikat von Debug/
- **Kann gelöscht werden**: Ja (nach Bestätigung dass Debug/ funktioniert)

## Wiederherstellung

Falls Code aus dem Archiv benötigt wird:
1. Dateien aus `unused_code/` zurück nach `TouchUpCore/` kopieren
2. Kommentare in `HIDInterpreter.c` entfernen (suche nach "ARCHIVED")
3. Projekt neu kompilieren
