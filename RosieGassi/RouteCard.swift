import SwiftUI
import MapKit
import RosieCore

struct RouteCard: View {
    let walk: Walk
    @Environment(GPSCoordinator.self) private var gps

    var body: some View {
        let geometry = walk.route?.estimatedGeometry(profile: gps.routeFilter)
        RuheCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("GPS-Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.headline)
                Text(gps.status(for: walk)).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("gps.status")
                Text("\(walk.route?.points.count ?? 0) GPS-Punkte gespeichert")
                    .accessibilityIdentifier("gps.pointCount")
                if let distance = geometry?.distanceMeters {
                    Text("Geschätzte GPS-Distanz: \(distance.formatted(.number.precision(.fractionLength(0)))) m")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gps.distance")
                } else {
                    Text("Geschätzte GPS-Distanz: Noch nicht verfügbar").font(.footnote)
                        .accessibilityIdentifier("gps.distanceMissing")
                }
                if gps.canAddTestPoint(walk.id) {
                    Button("DEMO: synthetischen GPS-Punkt speichern") { gps.addTestPoint(walk.id) }
                        .accessibilityIdentifier("gps.testPoint")
                }
                if walk.endedAt == nil, walk.route?.captureRequested == true {
                    if walk.route?.requiresCaptureConfirmation == true {
                        if gps.consent {
                            Button("GPS für diese wiederhergestellte Runde freigeben") { gps.confirmRestored(walk.id) }
                                .frame(minHeight: 44)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("gps.confirmRestored")
                        } else {
                            Text("Zuerst GPS-Routen unter Heute aktivieren. Wiederherstellen startet keine Aufnahme.").font(.footnote)
                        }
                    } else {
                        Button("GPS-Aufzeichnung beenden", role: .destructive) { gps.stopRoute(walk.id) }
                            .frame(minHeight: 44)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("gps.stop")
                    }
                }
                if let error = gps.error, walk.endedAt == nil {
                    Text("GPS: " + error).font(.footnote).foregroundStyle(.red)
                }
                if !(walk.route?.points.isEmpty ?? true) {
                    let drawable = (geometry?.segments ?? []).filter { !$0.isEmpty }
                    if drawable.contains(where: { $0.count >= 1 }) {
                        RouteMapCompact(segments: drawable)
                        Text("Geglättete Strecke aus gespeicherten Punkten. Kartenkacheln benötigen gegebenenfalls Internet. Zum Vergrößern auf die Karte tippen.").font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("GPS-Punkte gespeichert, aber keine verlässliche Strecke. Die grobe Linie braucht brauchbare Ortung.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("gps.unreliablePath")
                    }
                } else {
                    Text("Noch keine GPS-Punkte. Erfassung und Speicherung funktionieren ohne Internet; fehlende Signale können Lücken erzeugen.").font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if walk.endedAt == nil, walk.route != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GPS läuft auch in manuellen Pausen.")
                        Text("Bei beendeter App ist keine Aufnahme garantiert.")
                        Text("Gespeicherte Punkte bleiben beim Stoppen erhalten.")
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Immer sichtbare, kompakte Karte. Ein Tipp auf die Karte öffnet die große Ansicht.
private struct RouteMapCompact: View {
    let segments: [[RoutePoint]]
    @State private var showsDetail = false

    var body: some View {
        ZStack {
            RouteMapCanvas(segments: segments)
                .accessibilityHidden(true)
            Button {
                showsDetail = true
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gps.mapOpen")
            .accessibilityLabel("Karte der gespeicherten GPS-Route")
            .accessibilityHint("Öffnet die große Kartenansicht")
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.footnote.weight(.semibold))
                .padding(6)
                .background(.regularMaterial, in: Circle())
                .padding(8)
                .accessibilityHidden(true)
        }
        .sheet(isPresented: $showsDetail) {
            RouteMapDetailView(segments: segments)
        }
    }
}

/// Große, native Detailansicht mit eindeutigem Rückweg.
private struct RouteMapDetailView: View {
    let segments: [[RoutePoint]]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RouteMapCanvas(segments: segments)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityLabel("Karte der gespeicherten GPS-Route, große Ansicht")
                .accessibilityIdentifier("gps.mapDetail")
                .navigationTitle("Gespeicherte Route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                            .accessibilityIdentifier("gps.mapClose")
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }
}

/// Gemeinsame Kartendarstellung für kompakte und große Ansicht.
private struct RouteMapCanvas: View {
    let segments: [[RoutePoint]]

    var body: some View {
        Map {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, points in
                if points.count == 1, let point = points.first {
                    Marker("Gespeicherter GPS-Punkt", coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                } else if points.count > 1 {
                    MapPolyline(coordinates: points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(Color.accentColor, lineWidth: 4)
                }
            }
        }
    }
}
