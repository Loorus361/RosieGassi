import Foundation

/// Lokaler Bearbeitungsstand der Optionsliste eines Abstufungsfeldes.
///
/// Der Entwurf hält für jede Option die stabile `id` fest und erlaubt während der Eingabe
/// bewusst vorübergehend unvollständige Zeilen (leer, doppelt). Erst `makeOptions()`
/// übersetzt ihn in gültige `CustomFieldOption`-Werte und nutzt dafür die gemeinsame
/// Prüfung `CustomFieldDefinition.validateOptions`. Diese Trennung erlaubt es, Anlegen,
/// Umbenennen, Entfernen und Umsortieren unabhängig von der SwiftUI-Ansicht zu testen.
public struct CustomFieldOptionsDraft: Equatable, Sendable {
    /// Eine bearbeitbare Zeile. `id` bleibt über Umbenennen und Umsortieren hinweg stabil.
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var label: String

        public init(id: UUID = UUID(), label: String = "") {
            self.id = id
            self.label = label
        }
    }

    public var rows: [Row]

    public init(rows: [Row] = []) {
        self.rows = rows
    }

    /// Übernimmt die geordneten Optionen einer bestehenden Definition samt ID.
    public init(_ options: [CustomFieldOption]) {
        self.rows = options.map { Row(id: $0.id, label: $0.label) }
    }

    public init(_ definition: CustomFieldDefinition) {
        self.init(definition.orderedOptions)
    }

    public var isEmpty: Bool { rows.isEmpty }
    public var count: Int { rows.count }
    public var labels: [String] { rows.map(\.label) }
    public var ids: [UUID] { rows.map(\.id) }

    /// Fügt eine leere Zeile mit neuer stabiler ID an.
    @discardableResult
    public mutating func addRow() -> UUID {
        let id = UUID()
        rows.append(Row(id: id))
        return id
    }

    @discardableResult
    public mutating func remove(id: UUID) -> Bool {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return false }
        rows.remove(at: index)
        return true
    }

    public mutating func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where rows.indices.contains(index) {
            rows.remove(at: index)
        }
    }

    /// Ändert nur den Anzeigetext; die ID bleibt erhalten.
    public mutating func relabel(id: UUID, to label: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].label = label
    }

    public func canMoveUp(id: UUID) -> Bool {
        (rows.firstIndex { $0.id == id }).map { $0 > 0 } ?? false
    }

    public func canMoveDown(id: UUID) -> Bool {
        (rows.firstIndex { $0.id == id }).map { $0 < rows.count - 1 } ?? false
    }

    @discardableResult
    public mutating func moveUp(id: UUID) -> Bool {
        guard let index = rows.firstIndex(where: { $0.id == id }), index > 0 else { return false }
        rows.swapAt(index, index - 1)
        return true
    }

    @discardableResult
    public mutating func moveDown(id: UUID) -> Bool {
        guard let index = rows.firstIndex(where: { $0.id == id }), index < rows.count - 1 else { return false }
        rows.swapAt(index, index + 1)
        return true
    }

    /// Verschiebt die Zeilen mit derselben Semantik wie `Array.move(fromOffsets:toOffset:)` in SwiftUI.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { rows.indices.contains($0) }.sorted()
        guard !valid.isEmpty else { return }
        let moving = valid.map { rows[$0] }
        for index in valid.sorted(by: >) { rows.remove(at: index) }
        let adjusted = destination - valid.filter { $0 < destination }.count
        let insertAt = Swift.min(Swift.max(0, adjusted), rows.count)
        rows.insert(contentsOf: moving, at: insertAt)
    }

    /// Übersetzt den Entwurf in speicherbare Optionen. Wirft `CustomFieldError.invalidOptions`
    /// bei leerer Liste, leeren Beschriftungen oder doppelten IDs/Beschriftungen.
    public func makeOptions() throws -> [CustomFieldOption] {
        let options = try rows.map { try CustomFieldOption(id: $0.id, label: Self.normalized($0.label)) }
        try CustomFieldDefinition.validateOptions(options)
        return options
    }

    /// Anzeigetext normalisieren: außen trimmen und innere Leerraumfolgen zu einem Leerzeichen.
    static func normalized(_ label: String) -> String {
        label.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
