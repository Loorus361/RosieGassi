# Rosie Gassi

Native SwiftUI-iPhone-App für Carlos und Rosie. Runden starten, pausieren und beenden; Motivation, Lahmheit, Stationen, Notizen und eigene Felder erfassen. Optional GPS-Route, Wetter beim Start, Verlauf, Auswertung und Live Activity. Speichert offline mit SwiftData. Kein Server, keine KI-Laufzeit. Stand 0.1.0, Build 14; Deployment Target iOS 26.0. Oberfläche auf Deutsch.

RosieCore enthält Datenmodell, Speicherung, Auswertung und die Backup-/Restore-Tests. RosieGassi ist die SwiftUI-App. RosieGassiLiveActivity ist die Widget-Extension und liest keinen Store, startet kein GPS und geht nicht ins Netz. project.yml ist die XcodeGen-Quelle; nach Änderungen daran im Projektordner `xcodegen generate` ausführen. Einstieg: README.md. Datenregeln: docs/DATENVERTRAG.md. Buildbefehle: docs/BUILD.md.

## Bauen und prüfen

`RosieGassi.xcodeproj` öffnen, Scheme RosieGassi. Simulator-Befehle stehen in docs/BUILD.md; bei anderem Simulator die ID mit `xcrun simctl list devices available` holen. Der DEBUG-Schalter `--uitest-store` mit neuer UUID öffnet eine isolierte Vorschau ohne normale App-Daten, kein UI-Testlauf. Einmal bauen; bei sichtbaren Änderungen im Simulator einen Screenshot prüfen. Carlos klickt manuell durch.

Nur bei Backup, Restore, Datenmigration oder konkretem Datenverlustrisiko:

swift test --package-path RosieCore --scratch-path /tmp/RosieGassi-Core

Keine automatisierten UI-Tests, keine Test-first- oder Coverage-Pflicht. Bei Datenverlustrisiko nur unmittelbar betroffene Tests; keine Gesamtläufe, Testprotokolle oder Evidenzsammlungen für normale Änderungen. Mehr Prüfung nur bei konkretem Fehler oder ausdrücklichem Auftrag. Geräteupdate, Signierung, Provisionierung und Installation nur nach gesondertem Auftrag. Update datenerhaltend, niemals deinstallieren.

## Konventionen

Bestehenden funktionsfähigen Code weiterentwickeln; keine neue Architektur ohne konkreten Bedarf. Fehlende Scores bleiben nil, niemals 0 oder „normal“. Lahmheit und Motivation: 1 niedrig, 7 hoch. Historische Dezimalwerte nicht runden. Default-OK nur für Fahrstuhl, Flur und Hof neuer Runden. Gesamtzeit und manuelle Pausen getrennt aus Zeitstempeln ableiten; Pausen sind keine Ruhephasen. Eigene Felder behalten stabile ID und historische Revisionen; Archivieren löscht keine Werte. Gemischte Phasen nicht nach Spitzenwert bewerten. Keine Diagnose- oder Dosierungsratschläge.

Scores und eigene Ja/Nein-Felder bleiben ohne Antwort leer; historische Lücken und Skalen nicht still verändern. Änderungen eigener Felddefinitionen erzeugen neue Revisionen. Kein fortlaufender Hintergrundtimer für die Zeitberechnung. Keine kausalen Gesundheitsversprechen.

Apple-Systemkomponenten, SF Symbols, semantische Farben, Dynamic Type, VoiceOver, Reduce Motion/Transparency, Dark Mode und sichere Touch-Flächen beachten. Hintergrund-GPS und echtes Geräteverhalten beurteilt Carlos im Praxistest.

Offline-Speicherung ist Kern; Speicherformat, Validierung und Rollback erhalten. Netz-, Wetter- oder Live-Activity-Fehler dürfen keine Runde blockieren. GPS nur nach ausdrücklicher Einwilligung während gestarteter Runden. Wetter hat eine eigene Einwilligung zur Koordinatenübermittlung an Open-Meteo. Standortweitergabe separat bestätigen; keine versteckte Telemetrie oder öffentliche Veröffentlichung.

## Nicht anfassen

Keine echten Rosie-Dateien und keine normalen App-Daten für Entwicklung oder Prüfung lesen, ändern oder kopieren. Nur isolierte synthetische Daten. Die bisherige CSV bleibt bis zur ausdrücklichen Umstiegsfreigabe kanonisch. Bundle-IDs `de.carlosanderssohn.RosieGassi` und `de.carlosanderssohn.RosieGassi.LiveActivity`, Team `U8257B63WL` und die bestehende Datenidentität erhalten. Keine Käufe, Apple-Anmeldung, Zertifikatserstellung, Provisionierungsänderungen, System-/Xcode-Installation, Pushes oder Veröffentlichung ohne Auftrag. CloudKit und WeatherKit nicht aktivieren. Dieses lokale Git-Repository verwenden und nur auftragsbezogene Dateien committen; keine Produktionsdaten, Secrets, Zertifikate oder Provisioning Profiles aufnehmen.
