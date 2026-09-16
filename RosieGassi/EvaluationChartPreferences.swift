import Foundation
import RosieCore

/// Nur Anzeigeauswahl; Vorschauen verwenden die isolierte Kennzahlen-Suite.
struct EvaluationChartPreferences {
    private let defaults = EvaluationMetricsPreferencesStore.defaults()
    private let selectionKey = "evaluation.chart.selection.v1"
    private let dailyKey = "evaluation.chart.daily.v1"

    var selection: [EvaluationMetric] {
        guard let data = defaults.data(forKey: selectionKey),
              let values = try? JSONDecoder().decode([EvaluationMetric].self, from: data),
              !values.isEmpty else { return [.durationWithoutPauses, .lameness] }
        return values.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
    var daily: Bool { defaults.bool(forKey: dailyKey) }
    func save(selection: [EvaluationMetric]) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: selectionKey)
    }
    func save(daily: Bool) { defaults.set(daily, forKey: dailyKey) }
}
