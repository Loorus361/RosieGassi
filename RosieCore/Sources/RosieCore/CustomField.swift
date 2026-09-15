import Foundation

public enum CustomFieldKind: String, Codable, CaseIterable, Sendable {
    case scale = "skala"
    case boolean = "jaNein"
    case number = "zahl"
    /// Freie, geordnete Auswahl. Bewusst kein Zahlenwert: die Optionen sind reine Beschriftungen.
    case graded = "abstufung"

    public var displayName: String {
        switch self {
        case .scale: "Skala"
        case .boolean: "Ja/Nein"
        case .number: "Zahl"
        case .graded: "Abstufung"
        }
    }
}

public enum CustomFieldError: LocalizedError {
    case emptyName, invalidScale, invalidNumber, invalidValue, unknownField, invalidOrder, invalidOptions

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Bitte einen Namen für das Feld angeben."
        case .invalidScale: "Skala braucht einen gültigen Bereich, eine positive Schrittweite, die in den Bereich passt, und einen Endpunkt auf dem Raster."
        case .invalidNumber: "Bitte eine endliche Zahl eingeben, zum Beispiel 1,5."
        case .invalidValue: "Dieser Wert passt nicht zum Feld."
        case .unknownField: "Dieses Feld gehört nicht zur Runde."
        case .invalidOrder: "Die Reihenfolge der Felder ist unvollständig oder enthält unbekannte Einträge."
        case .invalidOptions: "Eine Abstufung braucht mindestens eine Option mit eindeutiger ID und eindeutiger, nicht leerer Beschriftung ohne führende oder abschließende Leerzeichen."
        }
    }
}

/// Eine frei beschriftete Option einer Abstufung. Die `id` ist die stabile Identität;
/// der Anzeigetext darf sich ändern, ohne dass gespeicherte Antworten ihre Zuordnung verlieren.
public struct CustomFieldOption: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let label: String

    public init(id: UUID = UUID(), label: String) throws {
        self.id = id
        self.label = label
        try validate()
    }

    public func validate() throws {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == label else { throw CustomFieldError.invalidOptions }
    }

    /// Gleiche stabile ID, neuer Anzeigetext.
    public func relabeled(_ label: String) throws -> CustomFieldOption {
        try CustomFieldOption(id: id, label: label)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: try container.decode(UUID.self, forKey: .id),
            label: try container.decode(String.self, forKey: .label)
        )
    }

    private enum CodingKeys: String, CodingKey { case id, label }
}

public enum DecimalText {
    public static func parse(_ raw: String) throws -> Double {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CustomFieldError.invalidNumber }
        if trimmed.contains(",") && trimmed.contains(".") { throw CustomFieldError.invalidNumber }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { throw CustomFieldError.invalidNumber }
        return value
    }

    public static func editingText(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if let exact = Int(exactly: value) { return String(exact) }
        return String(value).replacingOccurrences(of: ".", with: ",")
    }

    public static func displayText(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(0...8)))
    }
}

enum ScaleGrid {
    static func isAligned(_ value: Double, from origin: Double, step: Double) -> Bool {
        guard value.isFinite, origin.isFinite, step.isFinite, step > 0 else { return false }
        let count = ((value - origin) / step).rounded()
        guard count.isFinite else { return false }
        let reconstructed = origin + count * step
        let scale = max(abs(value), abs(origin), abs(step), abs(reconstructed), 1)
        return abs(reconstructed - value) <= scale * 1e-9
    }

    static func stepCount(from min: Double, to max: Double, step: Double) -> Int? {
        guard min.isFinite, max.isFinite, step.isFinite, min < max, step > 0 else { return nil }
        let span = max - min
        guard span.isFinite, step <= span, isAligned(max, from: min, step: step) else { return nil }
        let count = (span / step).rounded()
        guard let steps = Int(exactly: count), steps >= 1 else { return nil }
        return steps
    }

    static func snapped(_ value: Double, min: Double, max: Double, step: Double) -> Double {
        let clamped = Swift.min(max, Swift.max(min, value))
        let count = ((clamped - min) / step).rounded()
        if count <= 0 { return min }
        if let total = stepCount(from: min, to: max, step: step), count >= Double(total) { return max }
        return min + count * step
    }
}

public enum CustomFieldValue: Codable, Equatable, Sendable {
    case missing
    case scale(Double)
    case boolean(Bool)
    case number(Double)
    /// Genau eine Option einer Abstufung, referenziert über deren stabile ID. Unbeantwortet bleibt `.missing`.
    case choice(UUID)

    private enum CodingKeys: String, CodingKey { case kind, scale, boolean, number, choice }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "missing": self = .missing
        case "scale": self = .scale(try container.decode(Double.self, forKey: .scale))
        case "boolean": self = .boolean(try container.decode(Bool.self, forKey: .boolean))
        case "number": self = .number(try container.decode(Double.self, forKey: .number))
        case "choice": self = .choice(try container.decode(UUID.self, forKey: .choice))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown value kind")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .missing:
            try container.encode("missing", forKey: .kind)
        case .scale(let value):
            try container.encode("scale", forKey: .kind)
            try container.encode(value, forKey: .scale)
        case .boolean(let value):
            try container.encode("boolean", forKey: .kind)
            try container.encode(value, forKey: .boolean)
        case .number(let value):
            try container.encode("number", forKey: .kind)
            try container.encode(value, forKey: .number)
        case .choice(let id):
            try container.encode("choice", forKey: .kind)
            try container.encode(id, forKey: .choice)
        }
    }
}

public struct CustomFieldDefinition: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let revision: Int
    public let name: String
    public let kind: CustomFieldKind
    public let unit: String?
    public let scaleMin: Double?
    public let scaleMax: Double?
    public let scaleStep: Double?
    public let scaleLowLabel: String?
    public let scaleHighLabel: String?
    /// Nur für `.graded`: die geordnete Optionsliste. `nil` bei allen anderen Typen und in Altbeständen.
    public let options: [CustomFieldOption]?

    public static func make(
        id: UUID = UUID(),
        revision: Int = 1,
        name: String,
        kind: CustomFieldKind,
        unit: String? = nil,
        scaleMin: Double? = nil,
        scaleMax: Double? = nil,
        scaleStep: Double? = nil,
        scaleLowLabel: String? = nil,
        scaleHighLabel: String? = nil,
        options: [CustomFieldOption]? = nil
    ) throws -> CustomFieldDefinition {
        let definition = CustomFieldDefinition(
            id: id, revision: revision, name: name, kind: kind, unit: unit,
            scaleMin: scaleMin, scaleMax: scaleMax, scaleStep: scaleStep,
            scaleLowLabel: scaleLowLabel, scaleHighLabel: scaleHighLabel,
            options: options
        )
        try definition.validate()
        return definition
    }

    public func revising(
        name: String,
        kind: CustomFieldKind,
        unit: String? = nil,
        scaleMin: Double? = nil,
        scaleMax: Double? = nil,
        scaleStep: Double? = nil,
        scaleLowLabel: String? = nil,
        scaleHighLabel: String? = nil,
        options: [CustomFieldOption]? = nil
    ) throws -> CustomFieldDefinition {
        let (nextRevision, overflow) = revision.addingReportingOverflow(1)
        guard !overflow else { throw CustomFieldError.invalidValue }
        let next = try CustomFieldDefinition.make(
            id: id, revision: nextRevision, name: name, kind: kind, unit: unit,
            scaleMin: scaleMin, scaleMax: scaleMax, scaleStep: scaleStep,
            scaleLowLabel: scaleLowLabel, scaleHighLabel: scaleHighLabel,
            options: options
        )
        return hasSameContract(as: next) ? self : next
    }

    public func hasSameContract(as other: CustomFieldDefinition) -> Bool {
        id == other.id
            && name == other.name
            && kind == other.kind
            && unit == other.unit
            && scaleMin == other.scaleMin
            && scaleMax == other.scaleMax
            && scaleStep == other.scaleStep
            && scaleLowLabel == other.scaleLowLabel
            && scaleHighLabel == other.scaleHighLabel
            && options == other.options
    }

    public func validate() throws {
        guard revision >= 1 else { throw CustomFieldError.invalidValue }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName == name else { throw CustomFieldError.emptyName }
        let trimmedUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard unit == nil || (trimmedUnit?.isEmpty == false && trimmedUnit == unit) else { throw CustomFieldError.invalidValue }
        let low = scaleLowLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let high = scaleHighLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scaleLowLabel == nil || (low?.isEmpty == false && low == scaleLowLabel) else { throw CustomFieldError.invalidValue }
        guard scaleHighLabel == nil || (high?.isEmpty == false && high == scaleHighLabel) else { throw CustomFieldError.invalidValue }
        switch kind {
        case .boolean:
            guard unit == nil, scaleMin == nil, scaleMax == nil, scaleStep == nil,
                  scaleLowLabel == nil, scaleHighLabel == nil, options == nil else { throw CustomFieldError.invalidValue }
        case .number:
            guard scaleMin == nil, scaleMax == nil, scaleStep == nil,
                  scaleLowLabel == nil, scaleHighLabel == nil, options == nil else { throw CustomFieldError.invalidValue }
        case .scale:
            guard unit == nil, options == nil,
                  let min = scaleMin, let max = scaleMax, let step = scaleStep,
                  ScaleGrid.stepCount(from: min, to: max, step: step) != nil else { throw CustomFieldError.invalidScale }
        case .graded:
            guard unit == nil, scaleMin == nil, scaleMax == nil, scaleStep == nil,
                  scaleLowLabel == nil, scaleHighLabel == nil,
                  let options else { throw CustomFieldError.invalidValue }
            try Self.validateOptions(options)
        }
    }

    /// Gemeinsame Prüfung einer Optionsliste: mindestens eine Option, eindeutige IDs, eindeutige Beschriftungen,
    /// keine leeren oder außen mit Leerzeichen behafteten Texte.
    public static func validateOptions(_ options: [CustomFieldOption]) throws {
        guard !options.isEmpty else { throw CustomFieldError.invalidOptions }
        for option in options { try option.validate() }
        guard Set(options.map(\.id)).count == options.count,
              Set(options.map(\.label)).count == options.count else { throw CustomFieldError.invalidOptions }
    }

    /// Die Optionen in definierter Reihenfolge; bei anderen Typen leer.
    public var orderedOptions: [CustomFieldOption] { options ?? [] }

    public func option(_ id: UUID) -> CustomFieldOption? {
        options?.first { $0.id == id }
    }

    /// Anzeigetext eines Wertes über die stabile Options-ID. `nil` für unbeantwortet oder unbekannte Optionen.
    public func label(for value: CustomFieldValue) -> String? {
        guard case .choice(let id) = value else { return nil }
        return option(id)?.label
    }

    public var contractDescription: String {
        var parts = [kind.displayName, "Revision \(revision)"]
        switch kind {
        case .boolean:
            break
        case .number:
            if let unit, !unit.isEmpty { parts.append("Einheit \(unit)") }
        case .scale:
            if let min = scaleMin, let max = scaleMax, let step = scaleStep {
                parts.append("\(DecimalText.editingText(min))…\(DecimalText.editingText(max))")
                parts.append("Schritt \(DecimalText.editingText(step))")
            }
            if let scaleLowLabel { parts.append("unten \(scaleLowLabel)") }
            if let scaleHighLabel { parts.append("oben \(scaleHighLabel)") }
        case .graded:
            parts.append("\(orderedOptions.count) Stufen")
            if !orderedOptions.isEmpty { parts.append(orderedOptions.map(\.label).joined(separator: " → ")) }
        }
        return parts.joined(separator: " · ")
    }

    public func snapped(_ value: Double) -> Double {
        guard let min = scaleMin, let max = scaleMax, let step = scaleStep else { return value }
        return ScaleGrid.snapped(value, min: min, max: max, step: step)
    }

    public func advanced(from value: Double, steps: Int) -> Double {
        guard let min = scaleMin, let max = scaleMax, let step = scaleStep,
              let total = ScaleGrid.stepCount(from: min, to: max, step: step) else { return value }
        let current = ((snapped(value) - min) / step).rounded()
        let next = Swift.min(Double(total), Swift.max(0, current + Double(steps)))
        if next <= 0 { return min }
        if next >= Double(total) { return max }
        return min + next * step
    }

    func accepts(_ value: CustomFieldValue) throws {
        switch (kind, value) {
        case (_, .missing): return
        case (.scale, .scale(let amount)):
            guard let min = scaleMin, let max = scaleMax, let step = scaleStep,
                  amount.isFinite, amount >= min, amount <= max,
                  ScaleGrid.isAligned(amount, from: min, step: step) else { throw CustomFieldError.invalidValue }
        case (.boolean, .boolean): return
        case (.number, .number(let amount)):
            guard amount.isFinite else { throw CustomFieldError.invalidNumber }
        case (.graded, .choice(let id)):
            guard option(id) != nil else { throw CustomFieldError.invalidValue }
        default:
            throw CustomFieldError.invalidValue
        }
    }
}

public struct CustomFieldObservation: Codable, Equatable, Sendable {
    public let definition: CustomFieldDefinition
    public var value: CustomFieldValue

    public init(definition: CustomFieldDefinition, value: CustomFieldValue = .missing) throws {
        self.definition = definition
        self.value = value
        try validate()
    }

    public func validate() throws {
        try definition.validate()
        try definition.accepts(value)
    }
}

public struct CustomFieldCatalogEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { current.id }
    public var sortIndex: Int
    public var archived: Bool
    public var revisions: [CustomFieldDefinition]

    public var current: CustomFieldDefinition { revisions[revisions.count - 1] }

    public var displayedOrder: String {
        let (order, overflow) = sortIndex.addingReportingOverflow(1)
        return overflow ? "\(sortIndex)" : "\(order)"
    }

    public func validate() throws {
        let (_, overflow) = sortIndex.addingReportingOverflow(1)
        guard !overflow else { throw CustomFieldError.invalidValue }
        guard !revisions.isEmpty else { throw CustomFieldError.invalidValue }
        for (index, definition) in revisions.enumerated() {
            try definition.validate()
            guard definition.id == revisions[0].id, definition.revision == index + 1 else { throw CustomFieldError.invalidValue }
        }
    }

    func definition(revision: Int) -> CustomFieldDefinition? {
        revisions.first { $0.revision == revision }
    }
}

public struct CustomFieldCatalog: Codable, Equatable, Sendable {
    public static let empty = CustomFieldCatalog(entries: [])
    public var entries: [CustomFieldCatalogEntry]

    public var activeDefinitions: [CustomFieldDefinition] {
        entries.filter { !$0.archived }.sorted { $0.sortIndex < $1.sortIndex }.map(\.current)
    }

    public func entry(_ id: UUID) -> CustomFieldCatalogEntry? {
        entries.first { $0.id == id }
    }

    public func definition(id: UUID, revision: Int) -> CustomFieldDefinition? {
        entry(id)?.definition(revision: revision)
    }

    public mutating func insert(_ definition: CustomFieldDefinition) throws {
        try definition.validate()
        guard entry(definition.id) == nil, definition.revision == 1 else { throw CustomFieldError.invalidValue }
        let (sortIndex, overflow) = (entries.map(\.sortIndex).max() ?? -1).addingReportingOverflow(1)
        guard !overflow else { throw CustomFieldError.invalidValue }
        let entry = CustomFieldCatalogEntry(sortIndex: sortIndex, archived: false, revisions: [definition])
        try entry.validate()
        entries.append(entry)
    }

    public mutating func revise(_ definition: CustomFieldDefinition) throws {
        try definition.validate()
        guard let index = entries.firstIndex(where: { $0.id == definition.id }) else { throw CustomFieldError.unknownField }
        let current = entries[index].current
        if current.hasSameContract(as: definition) { return }
        let (nextRevision, overflow) = current.revision.addingReportingOverflow(1)
        guard !overflow, definition.revision == nextRevision else { throw CustomFieldError.invalidValue }
        entries[index].revisions.append(definition)
    }

    public mutating func archive(_ id: UUID) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw CustomFieldError.unknownField }
        entries[index].archived = true
    }

    public mutating func reorder(_ orderedIDs: [UUID]) throws {
        let active = entries.filter { !$0.archived }.sorted { $0.sortIndex < $1.sortIndex }.map(\.id)
        guard Set(orderedIDs).count == orderedIDs.count, Set(orderedIDs) == Set(active) else { throw CustomFieldError.invalidOrder }
        for (offset, id) in orderedIDs.enumerated() {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { throw CustomFieldError.invalidOrder }
            entries[index].sortIndex = offset
        }
        let archived = entries.indices.filter { entries[$0].archived }
        for (offset, index) in archived.enumerated() {
            entries[index].sortIndex = orderedIDs.count + offset
        }
    }

    public func validate() throws {
        for entry in entries { try entry.validate() }
        guard Set(entries.map(\.id)).count == entries.count else { throw CustomFieldError.invalidValue }
    }

    func matching(_ observation: CustomFieldObservation) throws {
        guard let stored = definition(id: observation.definition.id, revision: observation.definition.revision),
              stored == observation.definition else { throw CustomFieldError.invalidValue }
    }
}
