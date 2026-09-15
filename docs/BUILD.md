# Build und Start

Voraussetzungen: vorhandenes Xcode und XcodeGen. Deployment Target iOS 26.0; die vorhandene iPhone-17-Simulator-Runtime ist iOS 26.5. Alle Befehle im Projektordner ausführen.

## Simulator

```sh
xcodegen generate
xcodebuild build -project RosieGassi.xcodeproj -scheme RosieGassi \
  -destination 'platform=iOS Simulator,id=94A660CD-810C-4F33-9C51-A7840876E832' \
  -derivedDataPath /tmp/RosieGassi-Build CODE_SIGNING_ALLOWED=NO
xcrun simctl install 94A660CD-810C-4F33-9C51-A7840876E832 /tmp/RosieGassi-Build/Build/Products/Debug-iphonesimulator/RosieGassi.app
xcrun simctl launch --terminate-running-process 94A660CD-810C-4F33-9C51-A7840876E832 de.carlosanderssohn.RosieGassi --uitest-store "$(uuidgen)"
xcrun simctl io 94A660CD-810C-4F33-9C51-A7840876E832 screenshot /tmp/RosieGassi-preview.png
```

Der bestehende DEBUG-Schalter `--uitest-store` mit neuer UUID öffnet eine isolierte Vorschau ohne normale App-Daten. Er ist kein UI-Testlauf. Simulator vorher öffnen; bei verändertem Simulator die ID mit `xcrun simctl list devices available` ermitteln. Screenshot kurz visuell prüfen, Carlos klickt manuell durch.

Nur bei Backup-/Restore-/Migrationsrisiko gezielt testen:

```sh
swift test --package-path RosieCore --scratch-path /tmp/RosieGassi-Core
```

## Geräteupdate — nur nach gesondertem Auftrag

App **Rosie Gassi**, Bundle `de.carlosanderssohn.RosieGassi`, Extension `de.carlosanderssohn.RosieGassi.LiveActivity`, bestehendes Team `U8257B63WL`. Version 0.1.0, Build 13 für beide Targets in `project.yml`. Auf Fred zuletzt nachgewiesen: Build 12. IDs, Team und Datenformat für ein datenerhaltendes Update erhalten.

```sh
xcodebuild build -project RosieGassi.xcodeproj -scheme RosieGassi \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/RosieGassi-Device DEVELOPMENT_TEAM=U8257B63WL
```

Vorhandene Signierung zuerst ohne `-allowProvisioningUpdates`. Fehlende/abgelaufene Profile melden; keine Anmeldung, Zertifikatserstellung oder Provisionierungsänderung ohne Auftrag. Vor Installation Gerät mit `xcrun devicectl list devices` identifizieren. Nur `device install app` als Update verwenden, **niemals deinstallieren**. Anschließend Bundle/Version mit `device info apps --bundle-id` zurücklesen und App starten. Ohne Geräteantwort keine Installation behaupten. Keine normalen App-Daten für Prüfung auslesen; keine automatische CloudKit-/WeatherKit-Aktivierung.
