import Foundation

public enum WalkCSV {
    public static let columns = ["datum", "start", "ende", "dauer_min", "lahmheit_1_7", "motivation_1_7",
                                 "fahrstuhl", "flur", "hof", "bemerkung", "runde_id", "zeitzone",
                                 "start_iso", "ende_iso", "gesamtdauer_sek", "pausendauer_sek", "status", "exportiert_am_iso",
                                 "temperatur_c", "wetter_code", "niederschlag_mm", "wind_kmh", "wetter_ort",
                                 "wetter_quelle", "wetter_abgerufen_am_iso", "wetter_gueltig_am_iso", "wetter_intervall_sek",
                                 "bemerkung_formelschutz"]

    public static func encode(_ walks: [Walk], exportedAt: Date = Date()) throws -> Data {
        try WalkBackup.validateWalks(walks)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var rows = [columns.joined(separator: ",")]
        for walk in walks.sorted(by: { $0.startedAt < $1.startedAt }) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: walk.timeZoneID)
            formatter.dateFormat = "yyyy-MM-dd"
            let date = formatter.string(from: walk.startedAt)
            formatter.dateFormat = "HH:mm"
            let duration = walk.endedAt.map { walk.totalDuration(at: $0) }
            let pause = walk.endedAt.map { walk.pauseDuration(at: $0) }
            let stripped = walk.notes.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
            let protect = stripped.first.map { "=+-@".contains($0) } ?? false
            let note = protect ? "'" + walk.notes : walk.notes
            var values: [String] = [date, formatter.string(from: walk.startedAt), walk.endedAt.map { formatter.string(from: $0) } ?? ""]
            values += [duration.map { number(($0 / 60).rounded()) } ?? "", number(walk.lameness), number(walk.motivation)]
            values += [walk.elevator?.rawValue ?? "", walk.hallway?.rawValue ?? "", walk.courtyard?.rawValue ?? "", note]
            values += [walk.id.uuidString, walk.timeZoneID, iso.string(from: walk.startedAt), walk.endedAt.map { iso.string(from: $0) } ?? ""]
            values += [number(duration), number(pause), walk.endedAt == nil ? (walk.isPaused ? "pausiert" : "offen") : "abgeschlossen", iso.string(from: exportedAt)]
            values += [number(walk.weather?.temperatureCelsius), walk.weather?.weatherCode.map(String.init) ?? "",
                       number(walk.weather?.precipitationMm), number(walk.weather?.windSpeedKmh), walk.weather?.locationSource.rawValue ?? ""]
            let source = walk.weather?.source ?? ""
            let sourcePrefix = source.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))).first
            let safeSource = sourcePrefix.map { "=+-@".contains($0) } == true ? "'" + source : source
            values += [safeSource, walk.weather.map { iso.string(from: $0.fetchedAt) } ?? "",
                       walk.weather?.observedAt.map { iso.string(from: $0) } ?? "", number(walk.weather?.observationIntervalSeconds)]
            values.append(protect ? "ja" : "nein")
            rows.append(values.map(quote).joined(separator: ","))
        }
        return Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        let string = String(value)
        return string.hasSuffix(".0") ? String(string.dropLast(2)) : string
    }

    private static func quote(_ value: String) -> String {
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
