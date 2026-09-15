# Datenvertrag

## Speicherung, Zeit und Beobachtungen

SwiftData hält den versionierten Codable-Payload `Walk` in `StoredWalk`; die bestehende Tabellenstruktur bleibt erhalten. Autosave aus, CloudKit `.none`. Mutationen validieren, explizit speichern und erst danach veröffentlichen; bei Fehler Rollback. GPS-Mutationen übernehmen keine offenen Notizentwürfe.

Gesamtzeit läuft auch während manueller Pausen; Gesamt- und Pausenzeit entstehen aus Zeitstempeln. Zeit ohne manuelle Pause ist keine nachgewiesene Bewegungszeit. Start/Pause/Fortsetzen/Ende bleiben eigene Aktionen. Zeitkorrektur erfolgt über `WalkStore.update` und `correctTimes`: Ende nicht vor Start; offene Runden behalten `end == nil`, abgeschlossene werden nicht wieder geöffnet. Pausen müssen im Intervall bleiben. Verengung entfernt außerhalb liegende GPS-Punkte atomar, Erweiterung lässt sie stehen; niemals Zeitstempel verschieben.

Fünf Minuten nach Ende benötigen Änderungen eine ausdrückliche Bearbeitungsfreigabe. Verlassen, App-Wechsel oder Beenden der Bearbeitung widerruft diese; kein gespeicherter Entsperrstatus. Einzelnes Löschen braucht Bestätigung.

Scores 1–7: Motivation höher = besser, Lahmheit höher = stärker. Fehlend bleibt nil; vorhandene Dezimalwerte nicht runden. Default-OK nur für Fahrstuhl/Flur/Hof neuer Runden, kein Nachfüllen historischer Lücken. Anzeige „Schlecht“ behält den historischen Token `nein`. Keine medizinische Kausalinterpretation.

## Eigene Felder und Transfer

Vollbackup: `de.carlosanderssohn.RosieGassi.backup`, Schema **3**, Datumsformat `secondsSince2001-01-01T00:00:00Z`. Schema 1 und 2 bleiben lesbar. Fehlende Felder/Kataloge gelten als leer. Grenzen: 25 MiB je JSON, 100.000 Runden; Fehler statt stiller Kürzung. Restore validiert vor Übernahme, zeigt Konflikte, verlangt explizite Auswahl und verwirft bei Speicherfehler die ganze betroffene Übernahme. Veraltete Vorschauen und offene Entwürfe blockieren Transfer.

`fieldCatalog.entries` erhält unbenutzte und archivierte Definitionen mit `sortIndex`, `archived`, `revisions`. Definition: stabile UUID, Revision ab 1, Name, Typ, optionale Einheit und Skalen-/Beschriftungsparameter. Änderungen der Definition erzeugen neue Revisionen; Reihenfolge/Archivierung sind Metadaten. Neue Runden binden aktive Definitionen beim Start; bestehende Runden behalten unveränderliche Snapshots. Werte referenzieren ID und Revision, fehlend ist `missing`, nicht false/0. Referenz- und Katalogkonflikte niemals still umdeuten. Typ-Tokens: `skala`, `jaNein`, `zahl`, `abstufung`. Abstufungen sind geordnete Beschriftungen mit stabilen Options-UUIDs, keine Zahlenbewertungen; gespeicherte Auswahl `choice` verweist auf die Options-ID. Beschriftungs-/Optionsänderungen erhalten die historischen Definitionen; serialisierte Tokens und Revisionen nicht umdeuten.

Vollbackup enthält Route und Wetter samt Standortbezug; Weitergabe/Restore mit Standortdaten braucht gesonderte Bestätigung. Standortfreier Export: `de.carlosanderssohn.RosieGassi.location-free-export`, Schema 3, ohne GPS-/Wetterkoordinaten und **nicht wiederherstellbar**.

Kern-CSV bleibt kompatibel, ohne GPS-Koordinaten und eigene Felder. `eigene-felder.csv` ist ein Langformat in UTF-8, CRLF und RFC-Quoting: `walk_id,field_id,revision,name,type,unit,scale_min,scale_max,scale_step,value,options`. Eine Zeile je gebundener Definition, auch ohne Wert; Boolean ja/nein/leer, Dezimalpunkt, Formelschutz für führende `=+-@`. Bei Abstufungen enthält `value` die Options-UUID und `options` die geordnete Liste `id=label`, getrennt durch Semikolon; Backslash, Semikolon und Gleichheitszeichen in Beschriftungen werden mit Backslash maskiert. Die kanonische bisherige CSV wird nicht verändert.

## GPS

`Walk.route` bleibt optional; alte fehlende Routen sind nil. `RoutePoint` erhält Messzeit, Koordinaten, Genauigkeit und Segment-ID. Bewusste GPS-Aktivierung plus Systemberechtigung; danach vor jeder neuen Runde abschaltbar. Nur gestartete Runden, auch während manueller Pausen; Ende stoppt. Wiederhergestellte offene Routen bleiben bis zur erneuten ausdrücklichen Freigabe gesperrt.

Speicherfilter: endliche gültige Koordinaten, Genauigkeit 0–100 m, streng steigende Zeitstempel im Rundenintervall, keine Zukunft und höchstens 30 s Zustellalter. Über 60 s Lücke neues Segment; über 12 m/s innerhalb eines Segments verwerfen. Maximal 10.000 Punkte je Runde, keine Teilübernahme fehlerhafter Batches. Wiederanlauf trennt Segmente. Aufnahme fordert `kCLLocationAccuracyBest`, Distanzfilter 5 m.

Kartenlinie und geschätzte Distanz entstehen aus derselben abgeleiteten Geometrie: Genauigkeit höchstens 25 m, Gehprofil höchstens 3 m/s, Lücken über 60 s nicht verbinden. RDP-Toleranz 20/10/5 m für stärker geglättet/Standard/detaillierter; `gps.routeFilter` unbekannt oder fehlend bedeutet Standard. Nur Anzeige ändern, Rohpunkte/Backup unverändert. Keine brauchbare Strecke bleibt nil; keine erfundene 0. Gespeicherte GPS-Punkte garantieren keine Offline-Karte.

## Wetter

Eigene, standardmäßig ausgeschaltete Einwilligung zur Übermittlung von Koordinaten an Open-Meteo; Widerruf stoppt ausstehende Abrufe. Zuhause bewusst festlegen oder löschen. Kein WeatherKit.

Snapshot nur beim Start, mit Quelle, Ort, Abruf- und Modellzeit; historische Werte nicht später überschreiben. GPS der Runde, sonst bewusst gesetztes Zuhause; ohne Ort kein Wetter, Runde trotzdem. GPS-Start darf Zuhause nur bei fünf eindeutigen Lokalitätsbelegen der gestarteten Runde verwenden, deren Fehlerkreise vollständig innerhalb 10 km um Zuhause liegen. Keine alten oder zukünftigen Fixes, doppelte Beobachtungen nur einmal zählen; guter GPS-Fix hat Vorrang. Gemeinsames Start-/Abrufbudget 30 s; kein zweiter Snapshot durch spätere Ortung. Netzwerkfehler blockieren keine Runde.

## Auswertung

Kalenderwoche oder Kalendermonat in Europe/Berlin, ISO-Woche ab Montag; Intervall `start <= Rundenstart < ende`. Tageszeit nach Startzeit in der gespeicherten `Walk.timeZoneID`: vor 12, 12–18, ab 18. Auswahl nie leer, Standard alle.

Mittelwerte nur aus vorhandenen Werten, Nenner/Abdeckung sichtbar. Ein Punkt je Runde und Messreihe; fehlende Werte unterbrechen ausschließlich die betroffene Linie. Skala 1–7, keine Umrechnung. Offene Runden zählen, tragen aber keine feste Dauer zu Summen/Mitteln bei. Kartenstrecke und Kennzahlen nutzen dasselbe GPS-Anzeigeprofil. Diagramm und Kennzahlen erhalten dieselbe reine `WalkEvaluation`-Auswertung ohne eigene Uhr-/Persistenzzugriffe.

## Live Activity

App-ID `de.carlosanderssohn.RosieGassi`, Extension `de.carlosanderssohn.RosieGassi.LiveActivity`. Gemeinsame Typen in `LiveActivityShared`; Extension ohne Store, GPS, Netzwerk oder App Group. Gesamtzeitanzeige läuft in manueller Pause weiter.

Sitzung mit `walkID`, `sessionID`, eingefrorener Schnellvermerk-Definition und `activityID` als atomarer app-privater Sidecar unter `Application Support/LiveActivity`; kein Backup-/CSV-Bestandteil. Auswahl `liveActivity.quickNoteFieldID`: genau ein aktives Ja/Nein-Feld oder keines, beim Rundenstart an Definition und Revision binden.

Restore und Löschen der aktiven Runde setzen vor Datenersetzung einen dauerhaften Crash-Riegel. Solange Riegel/Invalidierung ungeklärt, keine Schreibaktion. Historisches Löschen darf eine andere laufende Sitzung nicht beenden.

Aktionen prüfen Riegel, passende Sitzung/Runde, tatsächlich gebundene laufende Activity und offene Runde; Vermerk zusätzlich exakte Feld-ID, Revision und gültige historische Definition. Archivierung/Typwechsel sperren. Pause/Fortsetzen nutzt Ausführungszeitpunkt; Schnellvermerk setzt ausschließlich Ja, wiederholt idempotent. Speicherfehler zeigen keinen Erfolg, Notizentwürfe unberührt.

Payload nur Zeit/Zustand, geschätzte Strecke, tatsächlich gespeicherte Punktzahl und Schnellvermerk; keine Rohpunkte oder Notizen. Feldname maximal 60 Zeichen, Budget 4096 Byte mit 256 Byte Reserve. Stale nach 60 s; reine GPS-Updates höchstens alle 10 s, Aktionen sofort. FIFO mit höchstens einem Update, nach Ende keine weiteren Updates. Abschluss beendet Activity; Neustart bindet passende Activities, entfernt verwaiste und erzeugt weggewischte nicht neu. Activity-Fehler blockieren weder Runde noch Speicherung oder GPS.
