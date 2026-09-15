import Foundation

/// Anzeige-Detailstufe der abgeleiteten GPS-Route.
///
/// Ändert ausschließlich die RDP-Toleranz der Anzeigeableitung
/// (`WalkRoute.estimatedGeometry(profile:)`). Gespeicherte Rohpunkte, Speicherfilter
/// und die festen Schutzfilter (Genauigkeit 25 m, Tempo 3 m/s) bleiben unverändert.
public enum RouteFilterProfile: String, CaseIterable, Codable, Sendable {
    /// Reihenfolge entspricht der UI-Reihenfolge: von stärker geglättet bis detaillierter.
    case smoothed
    case standard
    case detailed

    /// Heutiges Verhalten und sicherer Standard.
    public static let `default` = RouteFilterProfile.standard

    public var simplificationToleranceMeters: Double {
        switch self {
        case .smoothed: 20.0
        case .standard: WalkRoute.simplifyToleranceMeters
        case .detailed: 5.0
        }
    }

    public var displayName: String {
        switch self {
        case .smoothed: "Stärker geglättet"
        case .standard: "Standard"
        case .detailed: "Detaillierter"
        }
    }

    /// Liest einen persistierten Wert; fehlend oder unbekannt bedeutet Standard.
    public static func stored(_ rawValue: String?) -> RouteFilterProfile {
        rawValue.flatMap(RouteFilterProfile.init(rawValue:)) ?? .default
    }
}
