import Accessibility
import Charts
import JovraCore
import SwiftUI

/// The TrendCard of S03: first serves in for the latest week shown, the change in percentage points against the week
/// before, and a weekly line chart (0–100, three gridlines) that VoiceOver plays as an Audio Graph.
struct HomeTrendCard: View {
    var trend: HomeDashboard.Trend
    var isSample: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize >= .xxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Space.x2))
        VStack(alignment: .leading, spacing: Space.x1) {
            switch trend.state {
            case .ok:
                layout {
                    headline
                    HomeTrendChart(trend: trend)
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
            case .tooFewComparable:
                message(String(localized: "Play matches in two different weeks to see a trend.", table: "Home",
                               comment: "Trend card: not enough weeks with first serves to compare"))
                if !trend.weeks.allSatisfy(\.hidden) {
                    HomeTrendChart(trend: trend).frame(maxWidth: .infinity, minHeight: 160)
                }
            case .noData:
                message(String(localized: "Record a match to start your first-serve trend.", table: "Home",
                               comment: "Trend card: no match in the window"))
            }
            if trend.includesEstimated {
                Label(String(localized: "Includes estimated points", table: "Home", comment: "Trend card caption"),
                      systemImage: "sparkles")
                    .font(.jovraCaption)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .jovraCard(padding: Space.x2 + Space.half)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.trend")
    }

    @ViewBuilder private var headline: some View {
        if let headline = trend.headline {
            let presentation = FractionPresentation(ratio: headline.current, provenance: nil, isSample: isSample)
            let delta = deltaText(headline)
            VStack(alignment: .leading, spacing: Space.half) {
                Text("First serves in", tableName: "Home", comment: "Trend card label")
                    .font(.jovraLabel)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: presentation.value)
                    .font(.jovraMetricLarge)
                    .foregroundStyle(.jovra(.textPrimary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Label {
                    Text(verbatim: delta)
                } icon: {
                    Image(systemName: headline.deltaPoints > 0 ? "arrow.up" : headline.deltaPoints < 0 ? "arrow.down" : "equal")
                        .fontWeight(.bold)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.jovra(headline.deltaPoints >= 0 ? .accentInk : .attentionInk))
                .fixedSize(horizontal: false, vertical: true)
            }
            // Beside the chart the headline keeps to a column and its delta wraps; stacked it takes the full width.
            .frame(maxWidth: dynamicTypeSize >= .xxLarge ? .infinity : 148, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("First serves in", tableName: "Home"))
            .accessibilityValue(Text(verbatim: [presentation.spokenValue, delta].joined(separator: ", ")))
            .accessibilityIdentifier("home.trend.value")
        }
    }

    private func deltaText(_ headline: TrendHeadline) -> String {
        HomeCopy.delta(points: headline.deltaPoints,
                       versusWeek: headline.priorIndex == headline.currentIndex - 1 ? nil : headline.priorIndex)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.jovraBody)
            .foregroundStyle(.jovra(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Weekly pooled first serves in. Hidden buckets (too few serves to show) are gaps, never zeros.
struct HomeTrendChart: View {
    var trend: HomeDashboard.Trend
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Point: Identifiable {
        var index: Int
        var percent: Int
        var id: Int { index }
    }

    private var points: [Point] {
        trend.weeks.compactMap { week in
            guard !week.hidden, let percent = week.ratio.pct.value else { return nil }
            return Point(index: week.index, percent: percent)
        }
    }

    /// Every week, thinned to the first and last at accessibility text sizes (S03 Accessibility).
    private var xAxisLabels: [String] {
        let labels = trend.weeks.map { HomeCopy.shortWeekLabel($0.index) }
        guard dynamicTypeSize.isAccessibilitySize, labels.count > 2, let first = labels.first, let last = labels.last else { return labels }
        return [first, last]
    }

    var body: some View {
        let lastIndex = points.last?.index
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Week", HomeCopy.shortWeekLabel(point.index)), y: .value("Percent", point.percent))
                    .foregroundStyle(LinearGradient(colors: [Color.jovra(.chartArea), Color.jovra(.chartArea).opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Week", HomeCopy.shortWeekLabel(point.index)), y: .value("Percent", point.percent))
                    .foregroundStyle(Color.jovra(.chartLine))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Week", HomeCopy.shortWeekLabel(point.index)), y: .value("Percent", point.percent))
                    .symbol {
                        let isLast = point.index == lastIndex
                        Circle()
                            .fill(isLast ? Color.jovra(.accent) : Color.jovra(.chartLine))
                            .overlay(Circle().strokeBorder(Color.jovra(.chartLine), lineWidth: isLast ? 2 : 0))
                            .frame(width: isLast ? 14 : 9, height: isLast ? 14 : 9)
                    }
            }
        }
        .chartXScale(domain: trend.weeks.map { HomeCopy.shortWeekLabel($0.index) })
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Color.jovra(.chartGrid))
                AxisValueLabel().font(.caption2).foregroundStyle(Color.jovra(.textSecondary))
            }
        }
        .chartXAxis {
            AxisMarks { value in
                if let label = value.as(String.self), xAxisLabels.contains(label) {
                    AxisValueLabel(centered: true) {
                        Text(verbatim: label).font(.caption2).foregroundStyle(Color.jovra(.textSecondary))
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("First serves in by week", tableName: "Home", comment: "VoiceOver: the trend chart"))
        .accessibilityChartDescriptor(HomeTrendAudioGraph(trend: trend))
        .accessibilityIdentifier("home.trend.chart")
    }
}

/// The trend chart as an Audio Graph (VoiceOver: "Chart details" › "Play Audio Graph").
struct HomeTrendAudioGraph: AXChartDescriptorRepresentable {
    var trend: HomeDashboard.Trend

    func makeChartDescriptor() -> AXChartDescriptor { Self.descriptor(for: trend) }

    struct Point: Equatable {
        var week: String
        var percent: Int
        var fraction: String
    }

    /// The weeks shown, in order: hidden weeks (too few serves) are left out, never played as zero.
    static func points(for trend: HomeDashboard.Trend) -> [Point] {
        trend.weeks.compactMap { week in
            guard !week.hidden, let percent = week.ratio.pct.value else { return nil }
            return Point(week: HomeCopy.weekLabel(week.index), percent: percent,
                         fraction: String(localized: "\(week.ratio.n) of \(week.ratio.d)", table: "Home",
                                          comment: "Audio Graph: a week's fraction, e.g. “40 of 60”"))
        }
    }

    /// The Audio Graph: one category per week, the shown weeks' percentages, y from 0 to 100.
    static func descriptor(for trend: HomeDashboard.Trend) -> AXChartDescriptor {
        let name = String(localized: "First serves in", table: "Home", comment: "Trend chart series name")
        let categories = trend.weeks.map { HomeCopy.weekLabel($0.index) }
        let points = Self.points(for: trend).map { AXDataPoint(x: $0.week, y: Double($0.percent), label: $0.fraction) }
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: String(localized: "Week", table: "Home", comment: "Audio Graph x axis"), categoryOrder: categories)
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Percent", table: "Home", comment: "Audio Graph y axis"),
            range: 0...100, gridlinePositions: [0, 50, 100]) { value in
                JovraFormat.percent(Int(value.rounded()))
            }
        let summary = trend.headline.map { HomeCopy.delta(points: $0.deltaPoints) }
        return AXChartDescriptor(
            title: String(localized: "First serves in by week", table: "Home", comment: "Audio Graph title"),
            summary: summary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: name, isContinuous: true, dataPoints: points)])
    }
}
