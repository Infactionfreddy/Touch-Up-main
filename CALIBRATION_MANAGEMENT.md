# Kalibrierungsverwaltung Touch-Up

## Speicherort der Kalibrierungsdaten

Die Kalibrierungsdaten werden nun **extern** in JSON-Dateien gespeichert:

```
~/Library/Application Support/de.schafe.Touch-Up/calibrations/
```

Jeder Monitor hat eine eigene Datei:
- `screen_1.json` - Eingebautes Display
- `screen_4.json` - Externer Monitor (Display ID=4)

## Kalibrierung anzeigen

Um die Kalibrierungsdaten zu sehen:

```bash
cat ~/Library/Application\ Support/de.schafe.Touch-Up/calibrations/screen_4.json
```

Beispiel-Inhalt:
```json
{
  "displayID": 4,
  "touchA": {"x": 0.047, "y": 0.057},
  "touchB": {"x": 0.951, "y": 0.055},
  "touchC": {"x": 0.046, "y": 0.953},
  "touchD": {"x": 0.952, "y": 0.942},
  "screenA": {"x": -89, "y": 769},
  "screenB": {"x": -90, "y": 768},
  "screenC": {"x": -1827, "y": 770},
  "screenD": {"x": -88, "y": -199},
  "timestamp": 1704384000
}
```

## Kalibrierung löschen

### Option 1: Einzelne Kalibrierung löschen

```bash
rm ~/Library/Application\ Support/de.schafe.Touch-Up/calibrations/screen_4.json
```

### Option 2: Alle Kalibrierungen löschen

```bash
rm -rf ~/Library/Application\ Support/de.schafe.Touch-Up/calibrations/
```

Die App erstellt die Verzeichnisse automatisch beim nächsten Start neu.

## Kalibrierung sichern

Um deine aktuelle Kalibrierung zu sichern:

```bash
cp -r ~/Library/Application\ Support/de.schafe.Touch-Up/calibrations/ ~/Desktop/touchup-calibration-backup/
```

Zum Wiederherstellen:

```bash
cp -r ~/Desktop/touchup-calibration-backup/* ~/Library/Application\ Support/de.schafe.Touch-Up/calibrations/
```

## Terminal-Shortcuts

Speichere diese Zeilen in deiner `.zshrc` oder `.bash_profile`:

```bash
# Touch-Up Kalibrierung anzeigen
alias touchup-cal='cat ~/Library/Application\ Support/de.schafe.Touch-Up/calibrations/screen_*.json'

# Touch-Up Kalibrierung löschen
alias touchup-reset='rm -rf ~/Library/Application\ Support/de.schafe.Touch-Up/calibrations/ && echo "✅ Kalibrierung gelöscht"'

# Touch-Up Ordner öffnen
alias touchup-open='open ~/Library/Application\ Support/de.schafe.Touch-Up/'
```

Dann kannst du einfach folgende Befehle nutzen:
```bash
touchup-cal          # Zeigt aktuelle Kalibrierung
touchup-reset        # Löscht alles
touchup-open         # Öffnet Finder-Fenster
```

## Vorteile der JSON-Speicherung

✅ **Leicht zu verwalten** - Einfache Textdatei  
✅ **Leicht zu löschen** - Keine NSUserDefaults-Caching-Probleme  
✅ **Leicht zu sichern** - Einfach kopieren  
✅ **Lesbar** - Du kannst die Werte jederzeit prüfen  
✅ **Portierbar** - Datei kann zwischen Systemen kopiert werden  

---

**Hinweis:** Die alte NSUserDefaults-Methode führte zu hartnäckigen Cache-Problemen. Mit JSON-Dateien ist die Kalibrierung nun vollständig transparent und einfach zu verwalten.
