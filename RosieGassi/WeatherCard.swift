import SwiftUI
import RosieCore

enum WeatherConsentCopy {
    static let activation = "Wenn die Startseite sichtbar ist, wird aktuelles Wetter für dein gespeichertes Zuhause bei Open-Meteo angefragt — nicht fortlaufend im Hintergrund. Beim Start einer Runde wird einmal der GPS-Ort dieser Runde oder, ohne GPS, dein Zuhause übertragen. Dafür ist Internet nötig. GPS-Routen bleiben lokal. Du kannst Wetter jederzeit deaktivieren; laufende Anfragen werden abgebrochen. Gespeicherte Rundensnapshots bleiben unverändert."
    static let homeSaved = "Zuhause gespeichert"
}

struct WeatherSnapshotDetails: View {
    enum Kind {
        case homePreview
        case walkStart
    }

    let kind: Kind
    let snapshot: WeatherSnapshot
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 6 : 8) {
            Label {
                Text(title)
                    .accessibilityIdentifier(kind == .walkStart ? "weather.title" : "weather.home.title")
            } icon: {
                Image(systemName: snapshot.systemImage)
            }
            .font(.headline)
            Text(snapshot.summary)
                .font(dynamicTypeSize.isAccessibilitySize ? .headline : .title3.weight(.semibold))
                .accessibilityIdentifier(kind == .walkStart ? "weather.summary" : "weather.home.summary")
            Text(timeLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(kind == .walkStart ? "weather.time" : "weather.home.time")
            Text(placeLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(kind == .walkStart ? "weather.place" : "weather.home.place")
            Text("Wetterdaten: Open-Meteo.com (CC BY 4.0)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(kind == .walkStart ? "weather.attribution" : "weather.home.attribution")
        }
    }

    private var title: String {
        kind == .walkStart ? "Wetter beim Start" : "Wetter zu Hause"
    }

    private var placeLabel: String {
        snapshot.locationSource == .gps ? "Ort: GPS dieser Runde" : "Ort: Zuhause"
    }

    private var timeLabel: String {
        let instant = (snapshot.observedAt ?? snapshot.fetchedAt).formatted(date: .omitted, time: .shortened)
        switch kind {
        case .walkStart: return "Datenstand beim Start: \(instant)"
        case .homePreview: return "Stand \(instant)"
        }
    }
}

struct HomeWeatherCard: View {
    let weather: WeatherCoordinator
    var onConfirmExpanded: () -> Void

    var body: some View {
        RuheCard {
            switch weather.preview.status {
            case .disabled:
                statusBlock(systemImage: "cloud.slash", text: weather.preview.message)
                Text("Unter Daten kannst du Open-Meteo einmalig freigeben.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .needsExpandedConsent:
                statusBlock(systemImage: "cloud.sun", text: weather.preview.message)
                Button("Wetter für Zuhause bestätigen") { onConfirmExpanded() }
                    .accessibilityIdentifier("weather.home.confirmExpanded")
            case .missingHome:
                statusBlock(systemImage: "house", text: weather.preview.message)
                Text("Zuhause speichern bleibt lokal. Erst mit Wetter-Freigabe geht der Ort an Open-Meteo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Aktuellen Standort als Zuhause speichern") {
                    weather.captureHomeFromCurrentLocation()
                }
                .accessibilityIdentifier("weather.setHome")
                if !weather.homeMessage.isEmpty {
                    Text(weather.homeMessage)
                        .font(.footnote)
                        .accessibilityIdentifier("weather.homeStatus")
                }
            case .loading:
                ProgressView(weather.preview.message)
                    .accessibilityIdentifier("weather.home.status")
            case .ready:
                if let snapshot = weather.preview.snapshot {
                    WeatherSnapshotDetails(kind: .homePreview, snapshot: snapshot)
                    if weather.preview.isRefreshing {
                        Text("Wird aktualisiert …")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !weather.preview.message.isEmpty {
                        Text(weather.preview.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Aktualisieren") { weather.refreshHomePreview(force: true) }
                        .font(.footnote)
                        .accessibilityIdentifier("weather.home.retry")
                }
            case .unavailable:
                statusBlock(systemImage: "wifi.slash", text: weather.preview.message)
                Button("Erneut versuchen") { weather.refreshHomePreview(force: true) }
                    .accessibilityIdentifier("weather.home.retry")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weather.home.card")
    }

    private func statusBlock(systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Wetter", systemImage: systemImage).font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("weather.home.status")
        }
    }
}
