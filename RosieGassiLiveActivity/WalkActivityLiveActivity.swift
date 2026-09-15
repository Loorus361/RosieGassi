import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Sperrbildschirm- und Dynamic-Island-Darstellung einer laufenden Rosie-Runde.
///
/// Die Extension rendert ausschließlich den gelieferten `LiveActivityContentState`:
/// kein GPS, keine Ortung, kein Store, keine Schreibzugriffe. Pause/Fortsetzen ist der
/// deklarative, idempotente `SetPausedIntent` und läuft im App-Prozess. `Stopp` beendet die
/// Runde bewusst nicht selbst, sondern öffnet per `OpenURLIntent` den strikt an diese Runde
/// gebundenen Deep Link, der in der App die vorhandene Abschlussmaske „Runde beenden?“ zeigt.
///
/// Aufbau: drei kompakte Bereiche (Laufzeit+Zustand, Strecke+GPS-Punkte, zwei Aktionen).
/// Ohne Überschrift, Erklärtexte, Standzeit und Schnellvermerk – die Karte bleibt kurz genug,
/// um auf dem Sperrbildschirm nicht abgeschnitten zu werden.
struct WalkActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            WalkLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(WalkActivityDeepLink.url(walkID: context.attributes.walkID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WalkTimerText(state: context.state, showsHours: true)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityLabel("Laufzeit")
                        .accessibilityValue(WalkFormat.elapsed(context.state))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WalkStateLabel(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        // Zweiter Kernbereich: geschätzte Strecke + GPS-Punkte. Kurze Beschriftungen,
                        // damit die erweiterte Island auf schmalen Geräten nicht abschneidet.
                        HStack(alignment: .firstTextBaseline, spacing: 20) {
                            WalkDistanceMetric(state: context.state, caption: "Strecke")
                            WalkPointsMetric(state: context.state, caption: "Punkte")
                            Spacer(minLength: 0)
                        }
                        WalkActions(attributes: context.attributes, state: context.state)
                    }
                }
            } compactLeading: {
                // Kompakt bewusst nur die Zeit; ohne Stunden, damit es knapp bleibt.
                WalkTimerText(state: context.state, showsHours: false)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityLabel("Laufzeit")
                    .accessibilityValue(WalkFormat.elapsed(context.state))
            } compactTrailing: {
                WalkGPSIndicator(state: context.state)
            } minimal: {
                WalkMinimalIndicator(state: context.state)
            }
            .widgetURL(WalkActivityDeepLink.url(walkID: context.attributes.walkID))
            .keylineTint(WalkFormat.accent(for: context.state))
        }
    }
}

// MARK: - Sperrbildschirm

/// Drei kompakte Bereiche in einer Spalte: Laufzeit/Zustand, Strecke/Punkte, Aktionen.
/// Nicht `private`, damit die fokussierte Vorschau (schmale Breite/große Schrift) und
/// die Layout-Gegenprobe dieselbe produktive Ansicht rendern.
struct WalkLockScreenView: View {
    let attributes: WalkActivityAttributes
    let state: LiveActivityContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                WalkTimerText(state: state, showsHours: true)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel("Laufzeit")
                    .accessibilityValue(WalkFormat.elapsed(state))
                Spacer(minLength: 8)
                WalkStateLabel(state: state)
            }

            HStack(alignment: .firstTextBaseline, spacing: 20) {
                WalkDistanceMetric(state: state)
                WalkPointsMetric(state: state)
                Spacer(minLength: 0)
            }

            WalkActions(attributes: attributes, state: state)
        }
        .padding(10)
        // Der Sperrbildschirm erlaubt nur ~160 pt Höhe; eine harte Obergrenze für Dynamic Type
        // hält die drei Bereiche auch bei großer Schrift innerhalb des Budgets.
        .dynamicTypeSize(.small ... .xxxLarge)
    }
}

// MARK: - Kerndaten

private struct WalkDistanceMetric: View {
    let state: LiveActivityContentState
    var alignment: HorizontalAlignment = .leading
    var caption: String = "Strecke"

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(WalkFormat.distance(state.estimatedDistanceMeters, isEstimate: true))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strecke, geschätzt")
        .accessibilityValue(state.estimatedDistanceMeters == nil
                            ? "noch keine Schätzung"
                            : WalkFormat.distance(state.estimatedDistanceMeters, isEstimate: false))
    }
}

private struct WalkPointsMetric: View {
    let state: LiveActivityContentState
    var alignment: HorizontalAlignment = .leading
    var caption: String = "GPS-Punkte"

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(state.storedPointCount)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                WalkGPSIndicator(state: state)
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gespeicherte GPS-Messpunkte")
        .accessibilityValue("\(state.storedPointCount), GPS \(WalkFormat.gps(state.gpsStatus).label)")
    }
}

private struct WalkStateLabel: View {
    let state: LiveActivityContentState

    var body: some View {
        let paused = state.isPaused
        let finished = state.endedAt != nil
        Label(
            finished ? "Abgeschlossen" : (paused ? "Pausiert" : "Läuft"),
            systemImage: finished ? "flag.checkered" : (paused ? "pause.circle.fill" : "play.circle.fill")
        )
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(finished ? Color.secondary : (paused ? Color.orange : Color.green))
        .accessibilityLabel(finished ? "Zustand: abgeschlossen" : (paused ? "Zustand: pausiert" : "Zustand: läuft"))
    }
}

/// Höchstens ein kleines semantisches Symbol beim Punktstand – keine zusätzliche Statuszeile.
private struct WalkGPSIndicator: View {
    let state: LiveActivityContentState

    var body: some View {
        let status = WalkFormat.gps(state.gpsStatus)
        Image(systemName: status.symbol)
            .font(.caption)
            .foregroundStyle(status.color)
            .accessibilityHidden(true)
    }
}

/// Minimale Darstellung mit mehreren Activities: nur ein kurzes Zustandssymbol.
private struct WalkMinimalIndicator: View {
    let state: LiveActivityContentState

    var body: some View {
        if state.endedAt != nil {
            Image(systemName: "flag.checkered")
                .accessibilityLabel("Runde abgeschlossen")
        } else if state.isPaused {
            Image(systemName: "pause.fill")
                .accessibilityLabel("Runde pausiert")
        } else {
            Image(systemName: "figure.walk")
                .accessibilityLabel("Runde läuft")
        }
    }
}

// MARK: - Aktionen

private struct WalkActions: View {
    let attributes: WalkActivityAttributes
    let state: LiveActivityContentState

    var body: some View {
        if state.endedAt == nil {
            HStack(spacing: 12) {
                WalkPauseButton(attributes: attributes, state: state)
                WalkStopButton(walkID: attributes.walkID)
            }
        }
    }
}

/// Direkte Pause-/Fortsetzen-Aktion. Ohne laufende Runde keine Aktion.
private struct WalkPauseButton: View {
    let attributes: WalkActivityAttributes
    let state: LiveActivityContentState

    var body: some View {
        Button(intent: SetPausedIntent(
            walkID: attributes.walkID,
            sessionID: attributes.sessionID,
            paused: !state.isPaused
        )) {
            Label(state.isPaused ? "Fortsetzen" : "Pause",
                  systemImage: state.isPaused ? "play.fill" : "pause.fill")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .tint(state.isPaused ? Color.green : Color.orange)
        .accessibilityLabel(state.isPaused ? "Runde fortsetzen" : "Runde pausieren")
    }
}

/// `Stopp` beendet die Runde nicht selbst. Der Knopf öffnet über den strikt an die Runde
/// gebundenen Deep Link die App mit der vorhandenen Abschlussmaske „Runde beenden?“, in der
/// die vorgeschlagene Endzeit bestätigt oder der Abschluss abgebrochen werden kann.
private struct WalkStopButton: View {
    let walkID: UUID

    var body: some View {
        Button(intent: OpenURLIntent(WalkActivityDeepLink.finishURL(walkID: walkID))) {
            Label("Stopp", systemImage: "stop.fill")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .tint(.red)
        .accessibilityLabel("Runde beenden")
        .accessibilityHint("Öffnet die App mit der Abschlussmaske für diese Runde. Beendet wird erst dort nach Bestätigung.")
    }
}

// MARK: - Bausteine

private struct WalkTimerText: View {
    let state: LiveActivityContentState
    var showsHours: Bool

    var body: some View {
        if let endedAt = state.endedAt {
            Text(WalkFormat.duration(endedAt.timeIntervalSince(state.startedAt)))
        } else {
            // Systemseitig flüssig, aus dem gespeicherten Startzeitpunkt abgeleitet.
            // `pauseTime: nil`, weil die Gesamtzeit in manuellen Pausen weiterläuft.
            Text(timerInterval: state.startedAt...Date.distantFuture,
                 pauseTime: nil,
                 countsDown: false,
                 showsHours: showsHours)
        }
    }
}

// MARK: - Darstellungshelfer

enum WalkActivityDeepLink {
    static let scheme = "rosiegassi"
    static let host = "active-walk"
    static let finishAction = "finish"

    /// Muss mit dem Parser in `RosieActiveWalkLink.swift` (App-Target) übereinstimmen.
    static func url(walkID: UUID) -> URL {
        URL(string: "\(scheme)://\(host)/\(walkID.uuidString)")!
    }

    /// Deep Link, der in der App die Abschlussmaske genau dieser Runde öffnet.
    static func finishURL(walkID: UUID) -> URL {
        URL(string: "\(scheme)://\(host)/\(walkID.uuidString)?action=\(finishAction)")!
    }
}

enum WalkFormat {
    static func duration(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval))
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Aktuelle Gesamtdauer für die Accessibility-Ansage (Zahlenwert neben dem Timer).
    static func elapsed(_ state: LiveActivityContentState, at now: Date = Date()) -> String {
        duration((state.endedAt ?? now).timeIntervalSince(state.startedAt))
    }

    /// Strecke; `nil` bleibt „—“ (noch keine Schätzung), nie eine erfundene 0 m.
    static func distance(_ meters: Double?, isEstimate: Bool) -> String {
        guard let meters, meters.isFinite else { return "—" }
        let value: String
        if meters < 1_000 {
            value = "\(Int(meters.rounded())) m"
        } else {
            value = String(format: "%.2f", meters / 1_000).replacingOccurrences(of: ".", with: ",") + " km"
        }
        return isEstimate ? "≈ \(value)" : value
    }

    static func accent(for state: LiveActivityContentState) -> Color {
        if state.endedAt != nil { return .secondary }
        return state.isPaused ? .orange : .green
    }

    struct GPS {
        let symbol: String
        let label: String
        let color: Color
    }

    static func gps(_ raw: String) -> GPS {
        switch raw {
        case LiveActivityGPSStatusCode.recording:
            GPS(symbol: "location.fill", label: "zeichnet auf", color: .green)
        case LiveActivityGPSStatusCode.waiting:
            GPS(symbol: "location", label: "wartet", color: .secondary)
        case LiveActivityGPSStatusCode.denied:
            GPS(symbol: "location.slash.fill", label: "kein Zugriff", color: .red)
        case LiveActivityGPSStatusCode.interrupted:
            GPS(symbol: "location.slash", label: "unterbrochen", color: .orange)
        case LiveActivityGPSStatusCode.off:
            GPS(symbol: "location.slash", label: "aus", color: .secondary)
        default:
            GPS(symbol: "location", label: "Status offen", color: .secondary)
        }
    }
}

// MARK: - Vorschau für kleine Breite und große Schrift

#if DEBUG
extension WalkActivityAttributes {
    static var preview: WalkActivityAttributes {
        WalkActivityAttributes(
            walkID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            sessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )
    }
}

extension LiveActivityContentState {
    static var previewRunning: LiveActivityContentState {
        LiveActivityContentState(
            startedAt: Date().addingTimeInterval(-755),
            estimatedDistanceMeters: 375,
            storedPointCount: 94,
            gpsStatus: LiveActivityGPSStatusCode.recording,
            updatedAt: Date()
        )
    }

    static var previewPaused: LiveActivityContentState {
        LiveActivityContentState(
            startedAt: Date().addingTimeInterval(-2_730),
            isPaused: true,
            estimatedDistanceMeters: 1_240,
            storedPointCount: 318,
            gpsStatus: LiveActivityGPSStatusCode.waiting,
            updatedAt: Date()
        )
    }

    /// Ohne Schätzung: Die Strecke bleibt „—“ statt einer erfundenen 0 m.
    static var previewNoDistance: LiveActivityContentState {
        LiveActivityContentState(
            startedAt: Date().addingTimeInterval(-45),
            gpsStatus: LiveActivityGPSStatusCode.waiting,
            updatedAt: Date()
        )
    }
}

/// ActivityKit-Vorschau des echten Sperrbildschirms und der erweiterten Dynamic Island.
#Preview("Sperrbildschirm – läuft/pausiert", as: .content, using: WalkActivityAttributes.preview) {
    WalkActivityLiveActivity()
} contentStates: {
    LiveActivityContentState.previewRunning
    LiveActivityContentState.previewPaused
}

#Preview("Erweiterte Island", as: .dynamicIsland(.expanded), using: WalkActivityAttributes.preview) {
    WalkActivityLiveActivity()
} contentStates: {
    LiveActivityContentState.previewRunning
    LiveActivityContentState.previewPaused
}

/// Fokussierte Layout-Vorschau: schmale Breite (300 pt, iPhone-SE-Klasse) und große Schrift
/// (`.accessibility3`). Rendert dieselbe produktive `WalkLockScreenView` wie der Sperrbildschirm,
/// damit abgeschnittene oder überlappende Inhalte sofort auffallen.
#Preview("Sperrbildschirm – schmal & große Schrift", traits: .sizeThatFitsLayout) {
    VStack(spacing: 16) {
        WalkLockScreenView(attributes: .preview, state: .previewRunning)
        WalkLockScreenView(attributes: .preview, state: .previewPaused)
        WalkLockScreenView(attributes: .preview, state: .previewNoDistance)
    }
    .frame(width: 300)
    .padding(8)
    .background(.black)
    .dynamicTypeSize(.accessibility3)
    .environment(\.colorScheme, .dark)
}
#endif
