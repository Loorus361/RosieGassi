import Foundation

public enum CustomFieldCSV {
    public static let columns = ["walk_id", "field_id", "revision", "name", "type", "unit",
                                 "scale_min", "scale_max", "scale_step", "value", "options"]

    public static func encode(_ walks: [Walk], exportedAt: Date = Date()) throws -> Data {
        try WalkBackup.validateWalks(walks)
        _ = exportedAt
        var rows = [columns.joined(separator: ",")]
        for walk in walks.sorted(by: { $0.startedAt < $1.startedAt }) {
            for observation in walk.customFields {
                let definition = observation.definition
                var values = [walk.id.uuidString, definition.id.uuidString, String(definition.revision)]
                values.append(protect(definition.name))
                values.append(definition.kind.rawValue)
                values.append(protect(definition.unit ?? ""))
                values.append(number(definition.scaleMin))
                values.append(number(definition.scaleMax))
                values.append(number(definition.scaleStep))
                values.append(valueText(observation.value))
                values.append(optionText(definition.orderedOptions))
                rows.append(values.map(quote).joined(separator: ","))
            }
        }
        return Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func valueText(_ value: CustomFieldValue) -> String {
        switch value {
        case .missing: return ""
        case .boolean(true): return "ja"
        case .boolean(false): return "nein"
        case .scale(let amount), .number(let amount): return number(amount)
        case .choice(let id): return id.uuidString
        }
    }

    /// Optionsspalte: leer für alle anderen Feldtypen, sonst `<id>=<label>` je Option,
    /// mehrere Optionen mit `;` getrennt. In der Beschriftung werden Backslash, `;` und `=`
    /// mit einem Backslash maskiert, damit die geordnete Liste eindeutig lesbar bleibt.
    /// Die ID allein identifiziert eine Option; Beschriftungen sind nur Anzeigetext.
    private static func optionText(_ options: [CustomFieldOption]) -> String {
        options.map { escape($0.id.uuidString) + "=" + escape($0.label) }.joined(separator: ";")
    }

    private static func escape(_ value: String) -> String {
        var escaped = ""
        for character in value {
            if character == "\\" || character == ";" || character == "=" { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        let string = String(value)
        return string.hasSuffix(".0") ? String(string.dropLast(2)) : string
    }

    private static func protect(_ value: String) -> String {
        let stripped = value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        if let first = stripped.first, "=+-@".contains(first) { return "'" + value }
        return value
    }

    private static func quote(_ value: String) -> String {
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
