import Charts
import RosieCore
import SwiftUI

enum FlexibleEvaluationChartPalette {
    static func color(at index: Int) -> Color { EvaluationValueFormatting.color(index) }
}

/// One plot uses a shared coordinate space; the two axes only transform labels.
/// Additional units get separate plots with the exact same calendar domain.
struct FlexibleEvaluationChart: View {
    let result: FlexibleEvaluationResult
    let aggregation: EvaluationAggregation
    @Binding var selection: Date?

    private var groups: [[FlexibleEvaluationSeries]] {
        var groups: [[FlexibleEvaluationSeries]] = []
        for series in result.series where series.descriptor.kind == .numeric {
            if let index = groups.firstIndex(where: { compatible($0[0].descriptor, series.descriptor) }) {
                groups[index].append(series)
            } else { groups.append([series]) }
        }
        return groups
    }

    private func compatible(_ lhs: EvaluationMetricDescriptor, _ rhs: EvaluationMetricDescriptor) -> Bool {
        if let scale = lhs.scale { return rhs.scale == scale && rhs.unit == lhs.unit }
        guard rhs.scale == nil else { return false }
        if EvaluationValueFormatting.isDuration(lhs.metric) || EvaluationValueFormatting.isDuration(rhs.metric) {
            return EvaluationValueFormatting.isDuration(lhs.metric) && EvaluationValueFormatting.isDuration(rhs.metric)
        }
        // Unitless custom numbers have no shared measurement contract.
        return lhs.unit != nil && lhs.unit == rhs.unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if groups.count == 2 {
                numericPlot(groups[0], right: groups[1])
            } else {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    numericPlot(group, right: [])
                }
            }
            ForEach(result.series.filter { $0.descriptor.kind == .boolean }) { series in
                booleanPlot(series)
            }
            ForEach(result.series.filter { $0.descriptor.kind == .category || $0.descriptor.kind == .text }) { series in
                annotationPlot(series)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Auswertung mit \(result.series.count) Messreihen")
    }

    private func numericPlot(_ left: [FlexibleEvaluationSeries], right: [FlexibleEvaluationSeries]) -> some View {
        let leftRange = axisRange(left)
        let rightRange = axisRange(right)
        let series = left + right
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                axisTitle(left)
                Spacer(minLength: 12)
                if !right.isEmpty { axisTitle(right).multilineTextAlignment(.trailing) }
            }
            Chart {
                ForEach(series) { metric in
                    let range = left.contains(where: { $0.id == metric.id }) ? leftRange : rightRange
                    ForEach(metric.points) { point in
                        if let value = plottedValue(point, metric: metric) {
                            LineMark(x: .value("Zeit", point.date), y: .value(metric.descriptor.name, normalized(value, in: range)),
                                     series: .value("Abschnitt", "\(metric.id)-\(point.segmentIndex)"))
                                .foregroundStyle(color(metric))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .interpolationMethod(.linear)
                                .accessibilityHidden(true)
                            PointMark(x: .value("Zeit", point.date), y: .value(metric.descriptor.name, normalized(value, in: range)))
                                .foregroundStyle(color(metric))
                                .symbol(symbol(metric))
                                .symbolSize(45)
                                .accessibilityLabel(pointLabel(point, metric: metric))
                        }
                    }
                }
                selectionMark
            }
            .chartXScale(domain: result.interval.start...result.interval.end)
            .chartYScale(domain: 0.0...1.0)
            .chartYAxis {
                AxisMarks(position: .leading, values: ticks) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        Text(axisLabel(value.as(Double.self) ?? 0, range: leftRange))
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                AxisMarks(position: .trailing, values: ticks) { value in
                    AxisValueLabel {
                        Text(right.isEmpty ? "" : axisLabel(value.as(Double.self) ?? 0, range: rightRange))
                            .frame(width: 34, alignment: .leading)
                    }
                }
            }
            .chartXAxis { timeAxis }
            .chartXSelection(value: $selection)
            .frame(height: 220)
            ForEach(series) { metric in coverage(metric) }
        }
    }

    private func booleanPlot(_ series: FlexibleEvaluationSeries) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(EvaluationValueFormatting.title(series.descriptor)).font(.subheadline.weight(.semibold)).foregroundStyle(color(series))
            Chart {
                ForEach(series.points) { point in
                    if let value = booleanValue(point) {
                        if aggregation == .day {
                            LineMark(x: .value("Tag", point.date), y: .value("Anteil Ja", value),
                                     series: .value("Abschnitt", point.segmentIndex))
                                .foregroundStyle(color(series))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .accessibilityHidden(true)
                        }
                        PointMark(x: .value("Zeit", point.date), y: .value("Antwort", value))
                            .foregroundStyle(color(series))
                            .symbol(symbol(series))
                            .symbolSize(60)
                            .accessibilityLabel(pointLabel(point, metric: series))
                    }
                }
                selectionMark
            }
            .chartXScale(domain: result.interval.start...result.interval.end)
            .chartYScale(domain: 0.0...1.0)
            .chartYAxis {
                AxisMarks(position: .leading, values: aggregation == .day ? [0.0, 0.5, 1.0] : [0.0, 1.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        Text(aggregation == .day ? "\(Int((value.as(Double.self) ?? 0) * 100)) %" : ((value.as(Double.self) ?? 0) == 0 ? "Nein" : "Ja"))
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                AxisMarks(position: .trailing, values: [0.0, 1.0]) { _ in AxisValueLabel { Text("").frame(width: 34) } }
            }
            .chartXAxis { timeAxis }
            .chartXSelection(value: $selection)
            .frame(height: 130)
            coverage(series)
        }
    }

    private func annotationPlot(_ series: FlexibleEvaluationSeries) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(EvaluationValueFormatting.title(series.descriptor)).font(.subheadline.weight(.semibold)).foregroundStyle(color(series))
            Chart {
                ForEach(series.points) { point in
                    if point.textValue != nil {
                        PointMark(x: .value("Zeit", point.date), y: .value("Angabe", 0.5))
                            .symbol(symbol(series))
                            .symbolSize(65)
                            .foregroundStyle(color(series))
                            .accessibilityLabel(pointLabel(point, metric: series))
                    }
                }
                selectionMark
            }
            .chartXScale(domain: result.interval.start...result.interval.end)
            .chartYScale(domain: 0.0...1.0)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.5]) { _ in AxisValueLabel { Text("").frame(width: 34) } }
                AxisMarks(position: .trailing, values: [0.5]) { _ in AxisValueLabel { Text("").frame(width: 34) } }
            }
            .chartXAxis { timeAxis }
            .chartXSelection(value: $selection)
            .frame(height: 75)
            Text("Markierung antippen, um die Angaben zu lesen.").font(.caption).foregroundStyle(.secondary)
            coverage(series)
        }
    }

    @AxisContentBuilder private var timeAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: result.filter.period == .month ? 4 : 5)) { _ in
            AxisTick()
            if result.filter.period == .day {
                AxisValueLabel(format: .dateTime.hour().minute())
            } else {
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
    }

    @ChartContentBuilder private var selectionMark: some ChartContent {
        if let selection {
            RuleMark(x: .value("Auswahl", selection)).foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).accessibilityHidden(true)
        }
    }

    private func axisTitle(_ group: [FlexibleEvaluationSeries]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(group) { metric in
                Text(metric.descriptor.name + " · " + unit(metric.descriptor))
                    .foregroundStyle(color(metric))
                    .font(.caption.weight(.semibold))
            }
        }
    }
    private func unit(_ descriptor: EvaluationMetricDescriptor) -> String {
        if EvaluationValueFormatting.isDuration(descriptor.metric) { return "Min." }
        if let scale = descriptor.scale { return "\(DecimalText.displayText(scale.lowerBound))–\(DecimalText.displayText(scale.upperBound))" }
        return descriptor.unit ?? "Wert"
    }
    private func coverage(_ series: FlexibleEvaluationSeries) -> some View {
        Text("\(series.descriptor.name): \(series.sampleCount) von \(series.totalRoundCount) Runden" + direction(series.id))
            .font(.caption).foregroundStyle(.secondary)
    }
    private func direction(_ metric: EvaluationMetric) -> String {
        switch metric {
        case .motivation: " · höher = besser"
        case .lameness: " · höher = stärker"
        case .estimatedDistanceMeters: " · geschätzt"
        default: ""
        }
    }
    private func color(_ series: FlexibleEvaluationSeries) -> Color {
        FlexibleEvaluationChartPalette.color(at: result.series.firstIndex(where: { $0.id == series.id }) ?? 0)
    }
    private func symbol(_ series: FlexibleEvaluationSeries) -> BasicChartSymbolShape {
        let index = result.series.firstIndex(where: { $0.id == series.id }) ?? 0
        return switch index % 5 {
        case 0: .circle
        case 1: .diamond
        case 2: .square
        case 3: .triangle
        default: .cross
        }
    }
    private func plottedValue(_ point: FlexibleEvaluationPoint, metric: FlexibleEvaluationSeries) -> Double? {
        guard let value = point.numericValue, value.isFinite else { return nil }
        return EvaluationValueFormatting.isDuration(metric.id) ? value / 60 : value
    }
    private func booleanValue(_ point: FlexibleEvaluationPoint) -> Double? {
        if let value = point.booleanValue { return value ? 1 : 0 }
        return aggregation == .day ? point.numericValue : nil
    }
    private func pointLabel(_ point: FlexibleEvaluationPoint, metric: FlexibleEvaluationSeries) -> String {
        "\(metric.descriptor.name), \(point.date.formatted(date: .abbreviated, time: aggregation == .day ? .omitted : .shortened)): " +
            EvaluationValueFormatting.value(point, descriptor: metric.descriptor, aggregation: aggregation)
    }
    private var ticks: [Double] { [0, 0.25, 0.5, 0.75, 1] }
    private func normalized(_ value: Double, in range: ClosedRange<Double>) -> Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
    private func axisLabel(_ normalized: Double, range: ClosedRange<Double>) -> String {
        let value = range.lowerBound + normalized * (range.upperBound - range.lowerBound)
        return value.formatted(.number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(0...2)))
    }
    private func axisRange(_ group: [FlexibleEvaluationSeries]) -> ClosedRange<Double> {
        if let scale = group.first?.descriptor.scale { return scale }
        let values = group.flatMap { series in series.points.compactMap { plottedValue($0, metric: series) } }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let lower = min(0, low)
        let upper = max(0, high)
        let span = max(upper - lower, 1)
        let magnitude = pow(10, floor(log10(span / 4)))
        let rawStep = span / 4 / magnitude
        let step = (rawStep <= 1 ? 1 : rawStep <= 2 ? 2 : rawStep <= 5 ? 5 : 10) * magnitude
        let start = floor(lower / step) * step
        let end = max(start + step, ceil(upper / step) * step)
        return start...end
    }
}
