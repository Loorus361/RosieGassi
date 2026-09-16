# Rosie Gassi — Arbeitsregeln

Native SwiftUI-App für Carlos und Rosie. Sprache: Deutsch. Bestehenden funktionsfähigen Code weiterentwickeln; keine neue Architektur ohne konkreten Bedarf. Einstieg: README.md, bei Datenänderungen docs/DATENVERTRAG.md; Buildbefehle in docs/BUILD.md.

## Nicht verhandelbar

- Keine echten Rosie-Dateien oder normalen App-Daten für Entwicklung lesen, verändern oder kopieren. Isolierte synthetische Daten verwenden. Die bisherige CSV bleibt bis zur ausdrücklichen Umstiegsfreigabe kanonisch.
- Fehlende Scores bleiben nil, niemals automatisch normal oder 0. Lahmheit 1=niedrig, 7=hoch; Motivation 1=niedrig, 7=hoch. Historische Dezimalwerte beim Import nicht auf halbe Schritte runden oder historische Skalen still umrechnen.
- Gespeichertes Default-OK nur für Fahrstuhl, Flur und Hof neuer Runden. Scores und eigene Ja/Nein-Felder bleiben unbeantwortet; historische Lücken unverändert.
- Gemischte Phasen nicht nach Spitzenwert bewerten. Keine kausalen Gesundheitsversprechen, Diagnose- oder Dosierungsratschläge.
- Gesamtzeit und manuelle Pausen getrennt aus Zeitstempeln ableiten. Pausen sind keine automatischen Ruhe-/Bewegungsphasen; kein fortlaufender Hintergrundtimer nötig.
- Eigene Felder mit stabiler ID und historischer Definition erhalten. Änderungen an Definitionen erzeugen neue Revisionen; Archivieren löscht keine Werte.
- Offline-Speicherung ist Kern. Netz-, Wetter- oder Live-Activity-Fehler dürfen keine Runde blockieren. Speicherformat, Validierung und Rollback erhalten.
- GPS nur nach expliziter Einwilligung während gestarteter Runden. Wetter hat eine eigene Einwilligung zur Koordinatenübermittlung an Open-Meteo. Standortweitergabe separat bestätigen; keine versteckte Telemetrie oder öffentliche Veröffentlichung.
- Keine Käufe, Apple-Anmeldung, Zertifikatserstellung, Provisionierungsänderungen oder System-/Xcode-Installation ohne Auftrag. CloudKit/WeatherKit nicht automatisch aktivieren.
- Keine Pushes, Veröffentlichung oder Geräteinstallation ohne gesonderten Auftrag. Geräteupdates datenerhaltend, niemals deinstallieren. Bundle-IDs und bestehende Datenidentität erhalten.
- Dieses lokale Git-Repository verwenden und nur auftragsbezogene Dateien committen. Keine Produktionsdaten, Secrets, Zertifikate oder Provisioning Profiles aufnehmen.

## Schlanker Entwicklungsmodus

- Zügig umsetzen, einfache wartbare Lösungen bevorzugen. Keine Test-first-Pflicht oder Coverage-Ziele.
- Einmal bauen; bei sichtbaren Änderungen im Simulator öffnen, einen Screenshot erzeugen und auf grobe Layout-, Lesbarkeits- und Bedienfehler prüfen. Carlos übernimmt das kurze manuelle Durchklicken.
- Keine automatisierten UI-Tests. Automatisierte Tests nur bei Backup, Restore, Datenmigration oder vergleichbarem konkreten Datenverlustrisiko; dann nur unmittelbar betroffene kleine Tests.
- Keine Testprotokolle, Evidenzsammlungen, wiederholten Gegenproben oder Gesamtläufe für normale Änderungen. Mehr Prüfung nur bei konkretem Fehler oder ausdrücklichem Auftrag.
- Apple-Systemkomponenten, SF Symbols, semantische Farben, Dynamic Type, VoiceOver, Reduce Motion/Transparency, Dark Mode und sichere Touch-Flächen beachten. Hintergrund-GPS und echtes Geräteverhalten beurteilt Carlos im Praxistest.
