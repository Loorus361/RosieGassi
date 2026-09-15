# Rosie Gassi

Native, private iPhone-App für Gassi- und Mobilitätsbeobachtungen: Runden starten, pausieren und beenden; Motivation, Lahmheit, Stationen, Notizen und eigene versionierte Felder erfassen. Dazu kommen optionale GPS-Routen mit Karte und geschätzter Strecke, Wetter beim Start, Verlauf, Wochen-/Monatsauswertung und eine Live Activity mit Schnellvermerk.

Die App speichert offline mit SwiftData. JSON-Vollbackup/Restore, standortfreier Export und CSV dienen der bewussten Datenübergabe. Kein Server und keine KI-Laufzeit erforderlich. Die bisherige CSV bleibt bis zur ausdrücklichen Umstiegsfreigabe kanonisch.

**Aktueller Quellstand: 0.1.0, Build 13; iOS 26.0+. Auf Fred nachgewiesen: 0.1.0, Build 13 (Geräte-Metadaten vom 15.09.2026).** Wetterabruf draußen, Akkuverhalten und App-Wechsel funktionieren laut Carlos im Alltag.

## Aufbau und Einstieg

- `RosieCore/`: Datenmodell, Speicherung, Auswertung und fünf Testdateien mit 14 Backup-/Restore-/Transfer-Tests.
- `RosieGassi/`: SwiftUI-App, gemeinsame Live-Activity-Typen, Assets und App-Icon.
- `RosieGassiLiveActivity/`: WidgetKit-Extension.
- `project.yml`: XcodeGen-Projektdefinition; `RosieGassi.xcodeproj`: daraus erzeugtes Xcode-Projekt.

`RosieGassi.xcodeproj` in Xcode öffnen, Scheme **RosieGassi** wählen. Nach Änderungen an der Projektdefinition `xcodegen generate` im Projektordner ausführen.

Arbeitsregeln: [AGENTS.md](AGENTS.md). [Datenvertrag](docs/DATENVERTRAG.md), [Build und Start](docs/BUILD.md), [offene Wünsche und Praxistests](docs/WEITER.md).
