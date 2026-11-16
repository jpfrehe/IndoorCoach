import Charts
import SwiftUI

// MARK: - Theme

public enum Theme {
    public static let accent = Color(red: 0.98, green: 0.36, blue: 0.13)
    static let fitness = Color.blue
    static let fatigue = Color.pink
    static let indoor = Color(red: 0.98, green: 0.36, blue: 0.13)
    static let outdoor = Color.teal

    static func color(for zone: PowerZone) -> Color {
        switch zone {
        case .z1: Color(red: 0.55, green: 0.58, blue: 0.62)
        case .z2: Color(red: 0.20, green: 0.55, blue: 0.95)
        case .z3: Color(red: 0.20, green: 0.75, blue: 0.45)
        case .z4: Color(red: 0.98, green: 0.78, blue: 0.10)
        case .z5: Color(red: 0.98, green: 0.50, blue: 0.10)
        case .z6: Color(red: 0.92, green: 0.22, blue: 0.22)
        case .z7: Color(red: 0.60, green: 0.30, blue: 0.85)
        }
    }

    static func color(for type: WorkoutType) -> Color {
        switch type {
        case .recovery: color(for: .z1)
        case .endurance: color(for: .z2)
        case .tempo: color(for: .z3)
        case .sweetSpot, .threshold: color(for: .z4)
        case .vo2max: color(for: .z5)
        case .anaerobic, .sprint: color(for: .z6)
        case .test, .mixed: color(for: .z7)
        }
    }

    static func formColor(_ tsb: Double) -> Color {
        switch tsb {
        case ..<(-30): .red
        case ..<(-10): .orange
        case ..<5: .green
        case ..<25: .blue
        default: .gray
        }
    }

    static func formLabel(_ tsb: Double) -> String {
        switch tsb {
        case ..<(-30): "Überlastet"
        case ..<(-10): "Produktiv"
        case ..<5: "Ausgewogen"
        case ..<25: "Frisch"
        default: "Formverlust"
        }
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title).font(.subheadline.weight(.semibold))
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var unit: String? = nil
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
                if let unit { Text(unit).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TypeBadge: View {
    var type: WorkoutType
    var body: some View {
        Label(type.label, systemImage: type.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Theme.color(for: type))
            .background(Theme.color(for: type).opacity(0.15), in: Capsule())
    }
}

struct TypeIcon: View {
    var type: WorkoutType
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: type.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.color(for: type).gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

// MARK: - Power profile chart

struct PowerProfileChart: View {
    var definition: WorkoutDefinition
    var ftp: Int
    var showAxes = true
    var height: CGFloat = 180

    struct Bar: Identifiable {
        let id: Int
        let x0: Double, x1: Double, y: Double
        let zone: PowerZone
    }

    /// Ramps are split into slices so the stair-step shape follows the target power.
    var bars: [Bar] {
        var out: [Bar] = []
        var i = 0
        for step in definition.steps where step.duration > 0 {
            let slices = step.startPower == step.endPower ? 1 : max(4, step.duration / 60)
            let width = Double(step.duration) / Double(slices)
            for s in 0..<slices {
                let frac = (Double(s) + 0.5) / Double(slices)
                let p = step.startPower + (step.endPower - step.startPower) * frac
                let x0 = (Double(step.start) + width * Double(s)) / 60
                out.append(Bar(id: i, x0: x0, x1: x0 + width / 60, y: p * 100, zone: PowerZone(fractionOfFTP: p)))
                i += 1
            }
        }
        return out
    }

    var body: some View {
        let bars = self.bars
        let maxY = max(130, (bars.map(\.y).max() ?? 100) + 10)
        Chart {
            ForEach(bars) { bar in
                RectangleMark(xStart: .value("Start", bar.x0), xEnd: .value("Ende", bar.x1),
                              yStart: .value("Basis", 0), yEnd: .value("% FTP", bar.y))
                    .foregroundStyle(Theme.color(for: bar.zone).gradient)
            }
            RuleMark(y: .value("FTP", 100))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
                .annotation(position: .top, alignment: .leading) {
                    if showAxes { Text("FTP \(ftp) W").font(.caption2).foregroundStyle(.secondary) }
                }
        }
        .chartYScale(domain: 0...maxY)
        .chartXScale(domain: 0...(Double(definition.totalDuration) / 60))
        .chartXAxis {
            if showAxes {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))′") } }
                }
            }
        }
        .chartYAxis {
            if showAxes {
                AxisMarks(position: .leading, values: [50, 100, 150].filter { Double($0) <= maxY }) { value in
                    AxisGridLine()
                    AxisValueLabel { if let v = value.as(Int.self) { Text("\(v * ftp / 100) W") } }
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel("Leistungsprofil \(definition.title)")
    }
}

struct ZoneDistributionBar: View {
    var definition: WorkoutDefinition

    var body: some View {
        let zones = definition.timeInZones()
        let total = max(1, zones.values.reduce(0, +))
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(PowerZone.allCases) { zone in
                        if let seconds = zones[zone], seconds > 0 {
                            Theme.color(for: zone)
                                .frame(width: max(3, geo.size.width * Double(seconds) / Double(total) - 2))
                        }
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            FlowLegend(items: PowerZone.allCases.compactMap { zone in
                guard let s = zones[zone], s > 0 else { return nil }
                return (zone, "\(zone.shortName) \(Formatters.duration(s))")
            })
        }
    }
}

struct FlowLegend: View {
    var items: [(PowerZone, String)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.0) { zone, text in
                HStack(spacing: 6) {
                    Circle().fill(Theme.color(for: zone)).frame(width: 8, height: 8)
                    Text(text).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Rows

struct WorkoutRow: View {
    var workout: StoredWorkout
    var ftp: Int

    var body: some View {
        let d = workout.definition
        HStack(spacing: 12) {
            TypeIcon(type: d.type)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(workout.title).font(.body.weight(.semibold)).lineLimit(1)
                    if workout.status != .planned {
                        Image(systemName: workout.status.symbol)
                            .foregroundStyle(workout.status == .done ? .green : .secondary)
                    }
                    if workout.calendarEventID != nil {
                        Image(systemName: "calendar.badge.checkmark").foregroundStyle(.secondary).font(.caption)
                    }
                }
                Text(Self.dayLabel(workout.date)).font(.subheadline).foregroundStyle(.secondary)
                Text("\(Formatters.duration(d.totalDuration)) · TSS \(Int(d.estimatedTSS.rounded())) · IF \(Formatters.decimal(d.intensityFactor, digits: 2))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            PowerProfileChart(definition: d, ftp: ftp, showAxes: false, height: 34)
                .frame(width: 84)
                .opacity(workout.status == .skipped ? 0.4 : 1)
        }
        .padding(.vertical, 4)
    }

    static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute" }
        if cal.isDateInTomorrow(date) { return "Morgen" }
        if cal.isDateInYesterday(date) { return "Gestern" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE")))
    }
}

struct RideRow: View {
    var ride: RideSummary
    var ftp: Int
    var thresholdHeartRate: Int? = nil

    var body: some View {
        let est = TrainingLoad.estimateTSS(for: ride, ftp: ftp, thresholdHeartRate: thresholdHeartRate)
        HStack(spacing: 12) {
            Image(systemName: ride.isIndoor ? "figure.indoor.cycle" : "figure.outdoor.cycle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background((ride.isIndoor ? Theme.indoor : Theme.outdoor).gradient,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(ride.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(ride.startDate.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute().locale(Locale(identifier: "de_DE"))))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Formatters.duration(ride.movingTime)).font(.subheadline.weight(.medium)).monospacedDigit()
                HStack(spacing: 6) {
                    if let np = ride.weightedAverageWatts ?? ride.averageWatts { Text("\(Int(np)) W") }
                    Text("TSS \(Int(est.tss.rounded()))")
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}

struct EmptyStateView: View {
    var title: String
    var systemImage: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

struct BannerView: View {
    var banner: Banner
    var body: some View {
        Label(banner.message, systemImage: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(banner.isError ? Color.red : Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.horizontal)
    }
}

// MARK: - Platform helpers

extension View {
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    func numericKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }

    func plainTextInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }
}
