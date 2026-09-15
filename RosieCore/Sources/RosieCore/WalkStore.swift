import Foundation
import Observation
import SwiftData

@Model
final class StoredWalk {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var payload: Data

    init(walk: Walk) throws {
        id = walk.id
        schemaVersion = 1
        payload = try JSONEncoder().encode(walk)
    }
}

@Model
final class StoredCatalog {
    var schemaVersion: Int
    var payload: Data

    init(catalog: CustomFieldCatalog) throws {
        schemaVersion = 1
        payload = try JSONEncoder().encode(catalog)
    }
}

public enum StoreError: LocalizedError {
    case missingWalk, inconsistentArchive, editConfirmationRequired

    public var errorDescription: String? {
        switch self {
        case .missingWalk: "Diese Runde wurde nicht gefunden."
        case .editConfirmationRequired: "Diese Runde ist vor Änderungen geschützt. Bitte zuerst die nachträgliche Bearbeitung bestätigen."
        case .inconsistentArchive: "Der lokale Datenstand ist nicht lesbar oder enthält widersprüchliche Runden. Die Daten wurden nicht verändert."
        }
    }
}

/// Bestätigte Speicherereignisse für nachgelagerte Beobachter (Live Activity).
public enum WalkStoreChange: Equatable, Sendable {
    /// `isNew` ist nur bei einer wirklich NEU angelegten Runde wahr; das Öffnen einer
    /// bestehenden offenen Runde ist kein Start.
    case started(walkID: UUID, isNew: Bool)
    case updated(walkID: UUID)
    case deleted(walkID: UUID)
    /// Datenersetzung (Restore). Die aktive Runde danach, falls es eine gibt.
    case replaced(activeWalkID: UUID?)
}

@MainActor @Observable
public final class WalkStore {
    public private(set) var walks: [Walk] = []
    public private(set) var fieldCatalog = CustomFieldCatalog.empty
    // Failed note drafts stay visible across screens, never masquerading as persisted data.
    public private(set) var pendingNotes: [UUID: String] = [:]
    @ObservationIgnored private var weatherStarts = Set<UUID>()
    public func claimWeatherStart(_ id: UUID) -> Bool {
        weatherStarts.remove(id) != nil && activeWalk?.id == id
    }

    @ObservationIgnored public var weatherInvalidated: ((UUID) -> Void)?
    /// Eigener Subscriber für bestätigte Speichervorgänge (Live Activity). Bewusst
    /// getrennt von `weatherInvalidated`; wird nach erfolgreicher Veröffentlichung gerufen.
    @ObservationIgnored public var changeObserver: ((WalkStoreChange) -> Void)?
    /// Crash-Riegel vor einer Datenersetzung (Restore/Löschen). Wirft er, wird die
    /// Ersetzung gar nicht erst begonnen.
    @ObservationIgnored public var liveActivityFence: (() throws -> Void)?
    @ObservationIgnored private var needsRouteSegment = Set<UUID>()
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let persist: (ModelContext) throws -> Void

    public var activeWalk: Walk? { walks.first { $0.endedAt == nil } }

    public func backupData() throws -> Data {
        guard pendingNotes.isEmpty else { throw BackupError.unsavedNotes }
        return try WalkBackup.encode(walks, catalog: fieldCatalog)
    }

    public func locationFreeExportData() throws -> Data {
        guard pendingNotes.isEmpty else { throw BackupError.unsavedNotes }
        return try WalkBackup.encodeWithoutLocations(walks, catalog: fieldCatalog)
    }

    public func csvData() throws -> Data {
        guard pendingNotes.isEmpty else { throw BackupError.unsavedNotes }
        return try WalkCSV.encode(walks)
    }

    public func customFieldCSVData() throws -> Data {
        guard pendingNotes.isEmpty else { throw BackupError.unsavedNotes }
        return try CustomFieldCSV.encode(walks)
    }

    public func previewRestore(_ data: Data) throws -> RestorePreview {
        guard pendingNotes.isEmpty else { throw BackupError.unsavedNotes }
        return try RestorePreview(local: walks, catalog: fieldCatalog, backup: WalkBackup.decode(data))
    }

    public func restore(
        _ preview: RestorePreview,
        choices: [UUID: RestoreChoice] = [:],
        excluded: Set<UUID> = [],
        catalogChoices: [UUID: RestoreChoice] = [:]
    ) throws -> RestoreResult {
        guard pendingNotes.isEmpty else { throw BackupError.unsavedNotes }
        guard walks == preview.baseline, fieldCatalog == preview.catalogBaseline else { throw BackupError.stalePreview }
        guard excluded.isSubset(of: Set(preview.additions.map(\.id))) else { throw BackupError.invalidArchive }
        guard Set(choices.keys) == Set(preview.conflicts.map(\.id)),
              Set(catalogChoices.keys) == Set(preview.catalogConflicts.map(\.id)) else { throw BackupError.unresolvedConflicts }
        func disarm(_ walk: Walk) -> Walk {
            var copy = walk
            if copy.endedAt == nil, copy.route != nil { copy.route!.requiresCaptureConfirmation = true }
            return copy
        }
        let additions = preview.additions.filter { !excluded.contains($0.id) }.map(disarm)
        let replacements = preview.conflicts.filter { choices[$0.id] == .useBackup }.map(\.backup).map(disarm)
        let replacementMap = Dictionary(uniqueKeysWithValues: replacements.map { ($0.id, $0) })
        let candidate = walks.map { replacementMap[$0.id] ?? $0 } + additions
        var mergedCatalog = fieldCatalog
        mergedCatalog.entries.append(contentsOf: preview.catalogAdditions)
        for conflict in preview.catalogConflicts where catalogChoices[conflict.fieldID] == .useBackup {
            if let index = mergedCatalog.entries.firstIndex(where: { $0.id == conflict.fieldID }) {
                mergedCatalog.entries[index] = conflict.backup
            }
        }
        try WalkBackup.validateWalks(candidate, catalog: mergedCatalog)
        let catalogChanged = mergedCatalog != fieldCatalog
        // Riegel steht, bevor irgendein Datensatz ersetzt wird.
        try liveActivityFence?()
        do {
            for walk in additions { context.insert(try StoredWalk(walk: walk)) }
            for walk in replacements {
                let id = walk.id
                let descriptor = FetchDescriptor<StoredWalk>(predicate: #Predicate { $0.id == id })
                guard let row = try context.fetch(descriptor).first else { throw StoreError.missingWalk }
                row.payload = try JSONEncoder().encode(walk)
            }
            if catalogChanged { try applyCatalog(mergedCatalog) }
            if !additions.isEmpty || !replacements.isEmpty || catalogChanged { try persist(context) }
            walks = candidate.sorted { $0.startedAt > $1.startedAt }
            fieldCatalog = mergedCatalog
            for walk in replacements { weatherStarts.remove(walk.id); weatherInvalidated?(walk.id) }
            let result = RestoreResult(added: additions.count, replaced: replacements.count,
                                       skipped: preview.identicalCount + preview.conflicts.count - replacements.count + excluded.count)
            changeObserver?(.replaced(activeWalkID: activeWalk?.id))
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    public static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([StoredWalk.self, StoredCatalog.self])
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration("RosieGassi", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration("RosieGassi", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public init(container: ModelContainer, persist: @escaping (ModelContext) throws -> Void = { try $0.save() }) throws {
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.persist = persist
        let rows = try context.fetch(FetchDescriptor<StoredWalk>())
        let decoded = try rows.map { row in
            guard row.schemaVersion == 1 else { throw StoreError.inconsistentArchive }
            let walk = try JSONDecoder().decode(Walk.self, from: row.payload)
            guard walk.id == row.id else { throw StoreError.inconsistentArchive }
            try walk.validate()
            return walk
        }
        guard decoded.filter({ $0.endedAt == nil }).count <= 1 else { throw StoreError.inconsistentArchive }
        walks = decoded.sorted { $0.startedAt > $1.startedAt }
        let catalogRows = try context.fetch(FetchDescriptor<StoredCatalog>())
        guard catalogRows.count <= 1 else { throw StoreError.inconsistentArchive }
        if let row = catalogRows.first {
            guard row.schemaVersion == 1 else { throw StoreError.inconsistentArchive }
            let catalog = try JSONDecoder().decode(CustomFieldCatalog.self, from: row.payload)
            try catalog.validate()
            fieldCatalog = catalog
        }
        for walk in walks {
            for observation in walk.customFields {
                try fieldCatalog.matching(observation)
            }
        }
        needsRouteSegment = Set(decoded.filter { $0.endedAt == nil && $0.route != nil }.map(\.id))
    }

    public func createField(
        name: String,
        kind: CustomFieldKind,
        unit: String? = nil,
        scaleMin: Double? = nil,
        scaleMax: Double? = nil,
        scaleStep: Double? = nil,
        scaleLowLabel: String? = nil,
        scaleHighLabel: String? = nil,
        options: [CustomFieldOption]? = nil
    ) throws -> UUID {
        let definition = try CustomFieldDefinition.make(
            name: cleaned(name) ?? "",
            kind: kind,
            unit: cleaned(unit),
            scaleMin: scaleMin,
            scaleMax: scaleMax,
            scaleStep: scaleStep,
            scaleLowLabel: cleaned(scaleLowLabel),
            scaleHighLabel: cleaned(scaleHighLabel),
            options: options
        )
        var catalog = fieldCatalog
        try catalog.insert(definition)
        try writeCatalog(catalog)
        return definition.id
    }

    public func reviseField(
        _ id: UUID,
        name: String,
        kind: CustomFieldKind,
        unit: String? = nil,
        scaleMin: Double? = nil,
        scaleMax: Double? = nil,
        scaleStep: Double? = nil,
        scaleLowLabel: String? = nil,
        scaleHighLabel: String? = nil,
        options: [CustomFieldOption]? = nil
    ) throws {
        guard let current = fieldCatalog.entry(id)?.current else { throw CustomFieldError.unknownField }
        let next = try current.revising(
            name: cleaned(name) ?? "",
            kind: kind,
            unit: cleaned(unit),
            scaleMin: scaleMin,
            scaleMax: scaleMax,
            scaleStep: scaleStep,
            scaleLowLabel: cleaned(scaleLowLabel),
            scaleHighLabel: cleaned(scaleHighLabel),
            options: options
        )
        var catalog = fieldCatalog
        try catalog.revise(next)
        if catalog != fieldCatalog { try writeCatalog(catalog) }
    }

    public func archiveField(_ id: UUID) throws {
        var catalog = fieldCatalog
        try catalog.archive(id)
        if catalog != fieldCatalog { try writeCatalog(catalog) }
    }

    public func reorderFields(_ orderedIDs: [UUID]) throws {
        var catalog = fieldCatalog
        try catalog.reorder(orderedIDs)
        if catalog != fieldCatalog { try writeCatalog(catalog) }
    }

    @discardableResult
    public func start(at date: Date = Date(), recordRoute: Bool = false) throws -> UUID {
        if let activeWalk {
            changeObserver?(.started(walkID: activeWalk.id, isNew: false))
            return activeWalk.id
        }
        let observations = try fieldCatalog.activeDefinitions.map { try CustomFieldObservation(definition: $0) }
        let walk = Walk(startedAt: date, recordRoute: recordRoute, customFields: observations)
        try walk.validate()
        do {
            context.insert(try StoredWalk(walk: walk))
            try persist(context)
            walks.insert(walk, at: 0)
            weatherStarts.insert(walk.id)
            changeObserver?(.started(walkID: walk.id, isNew: true))
            return walk.id
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Domain eligibility only. Coordinator MUST additionally check global opt-in and OS permission.
    public func canRecordRoute(_ id: UUID) -> Bool {
        guard let walk = walks.first(where: { $0.id == id }) else { return false }
        return walk.endedAt == nil && walk.route?.captureRequested == true
            && walk.route?.requiresCaptureConfirmation != true
    }

    /// Invoke only after an explicit user decision to resume this restored open route.
    public func confirmRestoredRoute(_ id: UUID) throws {
        try writeRoute(id, allowingUnconfirmed: true) { walk in
            guard walk.route?.requiresCaptureConfirmation == true else { throw RouteError.captureDisabled }
            walk.route!.requiresCaptureConfirmation = nil
            walk.route!.beginSegment()
        }
    }

    /// Sensor writes deliberately bypass update(): pending note drafts remain untouched.
    @discardableResult
    public func appendRoutePoints(_ id: UUID, points: [RoutePoint], receivedAt: Date = Date()) throws -> Int {
        var accepted = 0
        try writeRoute(id) { walk in
            var route = walk.route!
            if needsRouteSegment.contains(id) { route.beginSegment() }
            accepted = try route.append(points, startedAt: walk.startedAt, receivedAt: receivedAt)
            if accepted > 0 { walk.route = route }
        }
        if accepted > 0 {
            needsRouteSegment.remove(id)
            changeObserver?(.updated(walkID: id))
        }
        return accepted
    }

    /// Call before resuming capture after a process restart or permission interruption.
    public func beginRouteSegment(_ id: UUID) throws {
        try writeRoute(id) { $0.route!.beginSegment() }
    }

    /// Permanent per-walk opt-out; a permission interruption should only begin a segment.
    public func stopRoute(_ id: UUID) throws {
        weatherInvalidated?(id)
        try writeRoute(id) { $0.route!.captureRequested = false; $0.route!.beginSegment() }
    }

    private func writeRoute(_ id: UUID, allowingUnconfirmed: Bool = false, change: (inout Walk) throws -> Void) throws {
        guard let index = walks.firstIndex(where: { $0.id == id }) else { throw StoreError.missingWalk }
        guard walks[index].endedAt == nil else { throw WalkError.completed }
        guard walks[index].route?.captureRequested == true,
              allowingUnconfirmed || canRecordRoute(id) else { throw RouteError.captureDisabled }
        var candidate = walks[index]
        try change(&candidate)
        try candidate.validate()
        guard candidate != walks[index] else { return }
        let payload = try JSONEncoder().encode(candidate)
        do {
            let descriptor = FetchDescriptor<StoredWalk>(predicate: #Predicate { $0.id == id })
            guard let row = try context.fetch(descriptor).first else { throw StoreError.missingWalk }
            row.payload = payload
            try persist(context)
            walks[index] = candidate
        } catch {
            context.rollback()
            throw error
        }
    }

    /// System weather write. Leaves note drafts untouched and never overwrites a stored snapshot.
    @discardableResult
    public func attachWeather(_ id: UUID, snapshot: WeatherSnapshot) throws -> Bool {
        guard let index = walks.firstIndex(where: { $0.id == id }) else { throw StoreError.missingWalk }
        if walks[index].weather != nil { return false }
        var candidate = walks[index]
        candidate.weather = snapshot
        try candidate.validate()
        let payload = try JSONEncoder().encode(candidate)
        do {
            let descriptor = FetchDescriptor<StoredWalk>(predicate: #Predicate { $0.id == id })
            guard let row = try context.fetch(descriptor).first else { throw StoreError.missingWalk }
            row.payload = payload
            try persist(context)
            walks[index] = candidate
            return true
        } catch {
            context.rollback()
            throw error
        }
    }

    public func delete(_ id: UUID) throws {
        guard let index = walks.firstIndex(where: { $0.id == id }) else { throw StoreError.missingWalk }
        // F3: Nur das Entfernen der laufenden Runde ersetzt die gebundenen Live-Activity-
        // Daten. Das Löschen einer historischen Runde darf die aktive Bindung nicht sperren.
        if walks[index].endedAt == nil { try liveActivityFence?() }
        do {
            let descriptor = FetchDescriptor<StoredWalk>(predicate: #Predicate { $0.id == id })
            guard let row = try context.fetch(descriptor).first else { throw StoreError.missingWalk }
            context.delete(row)
            try persist(context)
            walks.removeAll { $0.id == id }
            weatherInvalidated?(id)
            pendingNotes[id] = nil
            changeObserver?(.deleted(walkID: id))
        } catch {
            context.rollback()
            throw error
        }
    }

    public func updateNotes(_ id: UUID, text: String, at now: Date = Date(), confirmingEdit: Bool = false) throws {
        guard let walk = walks.first(where: { $0.id == id }) else { throw StoreError.missingWalk }
        // A keystroke can race the UI's lock refresh. Retain it as a draft only;
        // the persistent record still requires confirmation after the deadline.
        pendingNotes[id] = text == walk.notes ? nil : text
        try update(id, at: now, confirmingEdit: confirmingEdit) { $0.notes = text }
    }

    public func update(_ id: UUID, at now: Date = Date(), confirmingEdit: Bool = false, change: (inout Walk) throws -> Void) throws {
        guard let index = walks.firstIndex(where: { $0.id == id }) else { throw StoreError.missingWalk }
        guard confirmingEdit || !walks[index].requiresEditConfirmation(at: now) else {
            throw StoreError.editConfirmationRequired
        }
        var candidate = walks[index]
        candidate.notes = pendingNotes[id] ?? candidate.notes
        try change(&candidate)
        try candidate.validate()
        let payload = try JSONEncoder().encode(candidate)
        pendingNotes[id] = candidate.notes == walks[index].notes ? nil : candidate.notes
        do {
            let descriptor = FetchDescriptor<StoredWalk>(predicate: #Predicate { $0.id == id })
            guard let row = try context.fetch(descriptor).first else { throw StoreError.missingWalk }
            row.payload = payload
            try persist(context)
            walks[index] = candidate
            if candidate.endedAt != nil { weatherInvalidated?(id) }
            pendingNotes[id] = nil
            walks.sort { $0.startedAt > $1.startedAt }
            changeObserver?(.updated(walkID: id))
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Live-Activity-Pause/Fortsetzen. Nutzt denselben bestätigten Speicherpfad wie
    /// Sensor-/Systemschreibzugriffe und lässt Notizentwürfe (`pendingNotes`) unangetastet.
    /// Wiederholte Aufrufe sind No-ops ohne neuen Schreibvorgang.
    @discardableResult
    public func setPausedFromLiveActivity(_ id: UUID, paused: Bool, at date: Date) throws -> Walk {
        try mutateConfirmedWalkWithoutNotes(id) { walk in
            if paused {
                try walk.pause(at: date)
            } else {
                try walk.resume(at: date)
            }
        }
    }

    /// Schnellvermerk setzt ausschließlich Ja. Bereits Ja bleibt idempotent; ein Nein oder
    /// Zurücksetzen wird hier nie erzeugt. Die Revision wird vorher vom Aufrufer geprüft.
    @discardableResult
    public func markQuickNoteYesFromLiveActivity(_ id: UUID, fieldID: UUID) throws -> Walk {
        try mutateConfirmedWalkWithoutNotes(id) { walk in
            if case .boolean(true)? = walk.customFields.first(where: { $0.definition.id == fieldID })?.value { return }
            try walk.setCustomField(fieldID, value: .boolean(true))
        }
    }

    /// Kopiert den bestätigten Walk, ändert nur den gewünschten Zustand und
    /// veröffentlicht erst nach erfolgreichem Speichern. Kein Notizentwurf, kein
    /// Rollback-Leck: Bei einem Fehler bleibt der bestätigte Store unverändert.
    private func mutateConfirmedWalkWithoutNotes(_ id: UUID, change: (inout Walk) throws -> Void) throws -> Walk {
        guard let index = walks.firstIndex(where: { $0.id == id }) else { throw StoreError.missingWalk }
        guard walks[index].endedAt == nil else { throw WalkError.completed }
        var candidate = walks[index]
        try change(&candidate)
        try candidate.validate()
        guard candidate != walks[index] else { return walks[index] }
        let payload = try JSONEncoder().encode(candidate)
        do {
            let descriptor = FetchDescriptor<StoredWalk>(predicate: #Predicate { $0.id == id })
            guard let row = try context.fetch(descriptor).first else { throw StoreError.missingWalk }
            row.payload = payload
            try persist(context)
            walks[index] = candidate
            changeObserver?(.updated(walkID: id))
            return candidate
        } catch {
            context.rollback()
            throw error
        }
    }

    private func writeCatalog(_ catalog: CustomFieldCatalog) throws {
        try catalog.validate()
        do {
            try applyCatalog(catalog)
            try persist(context)
            fieldCatalog = catalog
        } catch {
            context.rollback()
            throw error
        }
    }

    private func applyCatalog(_ catalog: CustomFieldCatalog) throws {
        let rows = try context.fetch(FetchDescriptor<StoredCatalog>())
        guard rows.count <= 1 else { throw StoreError.inconsistentArchive }
        if let row = rows.first {
            guard row.schemaVersion == 1 else { throw StoreError.inconsistentArchive }
            row.payload = try JSONEncoder().encode(catalog)
        } else {
            context.insert(try StoredCatalog(catalog: catalog))
        }
    }

    private func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
