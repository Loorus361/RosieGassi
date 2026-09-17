# Rosie Gassi

Native iPhone-App für Gassi- und Mobilitätsbeobachtungen: Runden starten, pausieren und beenden; Motivation, Lahmheit, Stationen, Notizen und eigene versionierte Felder erfassen. Dazu kommen optionale GPS-Routen mit Karte und geschätzter Strecke, Wetter beim Start, Verlauf, Wochen-/Monatsauswertung und eine Live Activity mit Schnellvermerk.

Die App speichert offline mit SwiftData. JSON-Vollbackup/Restore, standortfreier Export und CSV dienen der bewussten Datenübergabe. Kein Server und keine KI-Laufzeit erforderlich. Die bisherige CSV bleibt bis zur ausdrücklichen Umstiegsfreigabe kanonisch.

**Aktueller Quellstand: 0.1.0, Build 14; iOS 26.0+. Auf Fred nachgewiesen: 0.1.0, Build 14 (Geräte-Metadaten vom 16.09.2026).** Wetterabruf draußen, Akkuverhalten und App-Wechsel funktionieren laut Carlos im Alltag.

## Aufbau und Einstieg

- `RosieCore/`: Datenmodell, Speicherung, Auswertung und fünf Testdateien mit 14 Backup-/Restore-/Transfer-Tests.
- `RosieGassi/`: SwiftUI-App, gemeinsame Live-Activity-Typen, Assets und App-Icon.
- `RosieGassiLiveActivity/`: WidgetKit-Extension.
- `project.yml`: XcodeGen-Projektdefinition; `RosieGassi.xcodeproj`: daraus erzeugtes Xcode-Projekt.

`RosieGassi.xcodeproj` in Xcode öffnen, Scheme **RosieGassi** wählen. Nach Änderungen an der Projektdefinition `xcodegen generate` im Projektordner ausführen.

Arbeitsregeln: [AGENTS.md](AGENTS.md). [Datenvertrag](docs/DATENVERTRAG.md), [Build und Start](docs/BUILD.md), [offene Wünsche und Praxistests](docs/WEITER.md).

## Flexible Auswertung

Im Tab Auswertung sind Tag, Kalenderwoche und Kalendermonat sowie einzelne Runden oder Tagesdurchschnitte wählbar. Die Tageszeitfilter wirken auch auf die Tagesmittel. Unter „Werte“ lassen sich beliebig viele Messwerte auswählen und sortieren; Auswahl und Zusammenfassung werden lokal gemerkt. Standard sind Dauer ohne manuelle Pausen und Lahmheit. Gesamtdauer und Pausenzeit bleiben separat verfügbar.

Zahlen mit kompatiblen Einheiten teilen sich eine Skala. Zwei Einheiten erhalten zwei beschriftete Achsen; weitere Einheiten werden in Diagrammen mit demselben Zeitbereich gezeigt. Ja/Nein erscheint je Runde als Antwort und pro Tag als Anteil Ja unter den beantworteten Runden. Kategorien und Notizen erscheinen als antippbare Markierungen. Eigene Feldversionen bleiben getrennt; fehlende Angaben werden nicht zu Nullwerten.

Für eine isolierte synthetische Vorschau: `--uitest-store <neue UUID> --uitest-evaluation-fixture`. Keine normalen App-Daten verwenden.

## Lizenz

Der Quellcode steht unter der [MIT-Lizenz](LICENSE). Abhängigkeiten behalten ihre jeweiligen Lizenzen.
