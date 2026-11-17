import Charts
import SwiftUI

// MARK: - Theme ("Sunset Jelly", tokens in Domain/Palette.swift)

public enum Theme {
    // Neutrals
    /// Plum-black for text and glyphs on jelly fills (never white on jelly: ≤ 2.6:1).
    static let ink = Color(Palette.ink)
    /// Warm paper behind cards (light) / black (dark).
    static let canvas = Color(light: Color(Palette.canvasLight), dark: Color(Palette.canvasDark))
    static let card = Color(light: Color(Palette.cardLight), dark: Color(Palette.cardDark))

    /// Tint for text, links and system controls: deep jelly berry in light mode (6.5:1), jelly pink in dark mode.
    public static let accent = Color(light: Color(Palette.accentTextLight), dark: Color(Palette.accentTextDark))
    /// Hero fill for primary actions, the week ring and selected chips – always with `ink` labels.
    static let sunset = LinearGradient(colors: [Color(Palette.peachFizz), Color(Palette.warmCoral), Color(Palette.jellyPink)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
    static let sunsetAngular = AngularGradient(colors: [Color(Palette.mangoPop), Color(Palette.peachFizz), Color(Palette.warmCoral),
                                                        Color(Palette.jellyPink)], center: .center,
                                               startAngle: .degrees(-90), endAngle: .degrees(270))
    /// Soft secondary surface (peach wash / pink wash in dark mode).
    static let softFill = Color(light: Color(Palette.peachFizz).opacity(0.32), dark: Color(Palette.jellyPink).opacity(0.18))

    // Data colours: jelly fill + deeper cap (≥ 3:1 against the card) for lines and thin marks.
    static let fitness = fill(.z2), fitnessLine = cap(.z2)
    static let fatigue = fill(.z6), fatigueLine = cap(.z6)
    static let indoor = fill(.z5), indoorMark = cap(.z5)
    static let outdoor = fill(.z2), outdoorMark = cap(.z2)
    static let done = cap(.z3)
    /// Chart axis labels: Swift Charts' default secondary grey is ~3.5:1 at caption2 size; this is ≥ 7:1.
    static let axisLabel = Color.primary.opacity(0.72)
    /// Small secondary text inside rows (caption/subheadline). System secondary is ~3.4:1 – too weak at caption size.
    static let rowSecondary = Color.primary.opacity(0.62)
    /// Swipe-action background behind white text (≥ 4.5:1).
    static let calendarAction = Color(red: 0.404, green: 0.443, blue: 0.671)
    /// Strava brand orange; darkened in light mode so "Mit Strava verbinden" reaches ≥ 4.5:1.
    static let strava = Color(light: Color(red: 0.80, green: 0.25, blue: 0.0), dark: Color(red: 0.99, green: 0.32, blue: 0.0))

    static func fill(_ zone: PowerZone) -> Color { Color(Palette.zones[zone.index].fill) }
    static func cap(_ zone: PowerZone) -> Color { Color(Palette.zones[zone.index].cap) }

    /// Zone colour (jelly fill). Kept as `color(for:)` so call sites read naturally.
    static func color(for zone: PowerZone) -> Color { fill(zone) }

    static func zone(for type: WorkoutType) -> PowerZone {
        switch type {
        case .recovery: .z1
        case .endurance: .z2
        case .tempo: .z3
        case .sweetSpot, .threshold: .z4
        case .vo2max: .z5
        case .anaerobic, .sprint: .z6
        case .test, .mixed: .z7
        }
    }

    static func color(for type: WorkoutType) -> Color { fill(zone(for: type)) }

    /// Form (TSB) states mapped onto the same jelly scale: fresh = cool, overreached = hot.
    static func formColor(_ tsb: Double) -> Color {
        switch tsb {
        case ..<(-30): fill(.z6)
        case ..<(-10): fill(.z5)
        case ..<5: fill(.z3)
        case ..<25: fill(.z2)
        default: fill(.z1)
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

extension PowerZone {
    /// Position on the Z1…Z7 scale (index into `Palette.zones`).
    var index: Int { PowerZone.allCases.firstIndex(of: self) ?? 0 }
}

extension Color {
    init(_ rgb: Palette.RGB) { self.init(red: rgb.r, green: rgb.g, blue: rgb.b) }
}

/// Jelly chip: solid fill + ink text. Used for type badges and the form state.
struct JellyChip: View {
    var text: String
    var systemImage: String?
    var fill: Color
    var body: some View {
        Group {
            if let systemImage { Label(text, systemImage: systemImage) } else { Text(text) }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(Theme.ink)
        .background(fill, in: Capsule())
    }
}

/// Primary action: sunset gradient with ink label (6.9–10:1), pressed feedback, dimmed when disabled.
struct JellyButtonStyle: ButtonStyle {
    var large = true
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((large ? Font.body : .subheadline).weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, large ? 18 : 12)
            .padding(.vertical, large ? 14 : 7)
            .frame(minHeight: 44)
            .background(Theme.sunset, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Secondary action: soft peach wash with accent text.
struct SoftButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .background(Theme.softFill, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

extension ButtonStyle where Self == JellyButtonStyle {
    static var jelly: JellyButtonStyle { JellyButtonStyle() }
    static var jellySmall: JellyButtonStyle { JellyButtonStyle(large: false) }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var soft: SoftButtonStyle { SoftButtonStyle() }
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var unit: String? = nil
    /// Optional jelly dot before the title (e.g. Fitness = periwinkle). Values stay in the primary text colour.
    var dot: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                // Never break a number across lines ("18 / 4" for 184 W at large Dynamic Type): shrink instead.
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let unit { Text(unit).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TypeBadge: View {
    var type: WorkoutType
    var body: some View {
        JellyChip(text: type.label, systemImage: type.symbol, fill: Theme.color(for: type))
    }
}

struct TypeIcon: View {
    var type: WorkoutType
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: type.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(Theme.color(for: type), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            // Deeper rim gives the pastel tile ≥ 3:1 against white cells (WCAG 1.4.11).
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(Theme.cap(Theme.zone(for: type)), lineWidth: 1.5))
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
                    .foregroundStyle(Theme.fill(bar.zone))
                // Jelly cap: the deeper tone gives every bar ≥ 3:1 against the card (WCAG 1.4.11).
                RectangleMark(xStart: .value("Start", bar.x0), xEnd: .value("Ende", bar.x1),
                              yStart: .value("Kappe", max(0, bar.y - maxY * 0.035)), yEnd: .value("% FTP", bar.y))
                    .foregroundStyle(Theme.cap(bar.zone))
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
                    AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))′").foregroundStyle(Theme.axisLabel) } }
                }
            }
        }
        .chartYAxis {
            if showAxes {
                AxisMarks(position: .leading, values: [50, 100, 150].filter { Double($0) <= maxY }) { value in
                    AxisGridLine()
                    AxisValueLabel { if let v = value.as(Int.self) { Text("\(v * ftp / 100) W").foregroundStyle(Theme.axisLabel) } }
                }
            }
        }
        .frame(height: height)
        // One element instead of one per bar slice (VoiceOver read 20–70 "x bis y" fragments).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Leistungsprofil \(definition.title)")
        .accessibilityValue(accessibilitySummary)
    }

    var accessibilitySummary: String {
        let peak = definition.steps.map { max($0.startPower, $0.endPower) }.max() ?? 0
        return "\(Formatters.duration(definition.totalDuration)), \(definition.segments.count) Abschnitte, "
            + "Spitze \(Int((peak * 100).rounded())) % FTP (\(Int((peak * Double(ftp)).rounded())) W)"
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let d = workout.definition
        HStack(spacing: 12) {
            if !typeSize.isAccessibilitySize { TypeIcon(type: d.type) }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(workout.title).font(.body.weight(.semibold)).lineLimit(2)
                    if workout.status != .planned {
                        Image(systemName: workout.status.symbol)
                            .foregroundStyle(workout.status == .done ? Theme.done : .secondary)
                    }
                    if workout.calendarEventID != nil {
                        Image(systemName: "calendar.badge.checkmark").foregroundStyle(Theme.rowSecondary).font(.caption)
                    }
                }
                Text(Self.dayLabel(workout.date)).font(.subheadline).foregroundStyle(Theme.rowSecondary)
                // IF lives in the detail; in the row it wrapped to "IF / 0,79" on 375 pt screens.
                Text("\(Formatters.duration(d.totalDuration)) · TSS \(Int(d.estimatedTSS.rounded()))")
                    .font(.caption).foregroundStyle(Theme.rowSecondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            // At accessibility text sizes the mini chart would squeeze the title to a few letters.
            if !typeSize.isAccessibilitySize {
                PowerProfileChart(definition: d, ftp: ftp, showAxes: false, height: 34)
                    .frame(width: 72)
                    .opacity(workout.status == .skipped ? 0.4 : 1)
            }
        }
        .padding(.vertical, 4)
    }

    static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute" }
        if cal.isDateInTomorrow(date) { return "Morgen" }
        if cal.isDateInYesterday(date) { return "Gestern" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "de_DE")))
    }
}

struct RideRow: View {
    var ride: RideSummary
    var ftp: Int
    var thresholdHeartRate: Int? = nil
    var heartRate: RelativeEffort.HeartRateProfile

    var body: some View {
        let est = TrainingLoad.estimateTSS(for: ride, ftp: ftp, thresholdHeartRate: thresholdHeartRate)
        HStack(spacing: 12) {
            Image(systemName: ride.isIndoor ? "figure.indoor.cycle" : "figure.outdoor.cycle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(ride.isIndoor ? Theme.indoor : Theme.outdoor,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(ride.isIndoor ? Theme.indoorMark : Theme.outdoorMark, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(ride.name).font(.body.weight(.semibold)).lineLimit(2)
                Text(ride.startDate.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute().locale(Locale(identifier: "de_DE"))))
                    .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Formatters.duration(ride.movingTime)).font(.subheadline.weight(.medium)).monospacedDigit()
                HStack(spacing: 6) {
                    if let np = ride.weightedAverageWatts ?? ride.averageWatts { Text("\(Int(np)) W") }
                    Text("TSS \(Int(est.tss.rounded()))")
                    if let effort = RelativeEffort.estimate(for: ride, heartRate: heartRate).value {
                        Text("RE \(Int(effort.rounded()))")
                    }
                }
                .font(.caption).foregroundStyle(Theme.rowSecondary).monospacedDigit()
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

extension Color {
    /// Light/dark variant without an asset catalog (the package also renders snapshots on macOS).
    init(light: Color, dark: Color) {
        #if os(iOS)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
        self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light) })
        #endif
    }
}

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

    /// API keys / client secrets are not account passwords: without this, Client-ID + Client-Secret look like a
    /// login form and iOS shows "Passwort sichern?" when the user leaves the screen, blocking the next tap.
    func credentialInput() -> some View {
        #if os(iOS)
        textContentType(.oneTimeCode)
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
