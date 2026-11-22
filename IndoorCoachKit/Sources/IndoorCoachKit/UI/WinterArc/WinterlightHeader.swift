import Charts
import SwiftUI

/// Kopf des Winter-Arc-Hubs (docs/22, B3): Himmel mit Schnee und Sonne, darunter auf Kartenweiß der Tageslicht-Gewinn, die
/// Zeile bis zum Ziel, ein kleines Diagramm und die ehrliche Fußnote (Näherung je Zeitzone, keine Ortung). Text steht nie auf
/// dem Himmel. Funktioniert ohne Verbindung, Daten und Claude.
struct WinterlightHeader: View {
    /// Saisonfortschritt 0…1 (steuert Himmel und Schnee).
    var progress: Double
    var start: Date
    var goal: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var glow = 0.6

    var body: some View {
        let calendar = Calendar.current
        let today = AppModel.today
        let latitude = Daylight.latitude(for: calendar.timeZone)
        let phase = Daylight.phase(now: today, latitude: latitude, calendar: calendar)
        let animated = visible && scenePhase == .active && CelebrationMotion.allowsParticleMotion(reduceMotion: reduceMotion, lowPowerMode: lowPower)
        VStack(spacing: 0) {
            sky(phase: phase, today: today, latitude: latitude, calendar: calendar, animated: animated)
                .frame(height: 180)
            VStack(alignment: .leading, spacing: 10) {
                Text(Daylight.line(for: phase)).font(.headline)
                    .accessibilityLabel(Daylight.spokenLine(for: phase))
                    .accessibilityIdentifier("winterlight.line")
                if let goalLine = Daylight.goalLine(now: today, goal: goal, latitude: latitude, calendar: calendar) {
                    Text(goalLine).font(.subheadline).foregroundStyle(Theme.rowSecondary)
                }
                chart(today: today, latitude: latitude, calendar: calendar)
                Text(Daylight.footnote(for: calendar.timeZone)).font(.caption).foregroundStyle(Theme.rowSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .task(id: phase) {
            // Am 21.12. leuchtet die Sonne einmal sanft auf (1 s); ohne Bewegung steht sie gleich heller.
            if phase == .solstice, !reduceMotion {
                glow = 0.4
                withAnimation(.easeInOut(duration: 1)) { glow = 1 }
            } else {
                glow = phase == .solstice ? 1 : 0.8
            }
        }
    }

    private func sky(phase: Daylight.Phase, today: Date, latitude: Double, calendar: Calendar, animated: Bool) -> some View {
        let stops = WinterSky.stops(progress: progress).map { Color($0) }
        let sun = Daylight.sunFraction(now: today, goal: goal, latitude: latitude, calendar: calendar)
        return ZStack {
            LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
            SnowfallCanvas(progress: progress, animated: animated)
            Canvas { context, size in
                let horizon = size.height * 0.84
                let r: CGFloat = 20
                let center = CGPoint(x: size.width * 0.74, y: horizon - 14 - CGFloat(sun) * size.height * 0.5)
                let color = Color(Palette.RGB(hex: 0xFFE9A8))
                let g = r * 3.2
                context.fill(Path(ellipseIn: CGRect(x: center.x - g, y: center.y - g, width: g * 2, height: g * 2)),
                             with: .radialGradient(Gradient(colors: [color.opacity(0.6 * glow), color.opacity(0)]), center: center,
                                                   startRadius: 0, endRadius: g))
                context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(color))
                var hills = Path()
                hills.move(to: CGPoint(x: 0, y: size.height))
                hills.addLine(to: CGPoint(x: 0, y: horizon))
                hills.addCurve(to: CGPoint(x: size.width, y: horizon + 4), control1: CGPoint(x: size.width * 0.3, y: horizon - 22),
                               control2: CGPoint(x: size.width * 0.65, y: horizon + 16))
                hills.addLine(to: CGPoint(x: size.width, y: size.height))
                hills.closeSubpath()
                context.fill(hills, with: .color(Color(Palette.RGB(hex: 0x3B3C86)).opacity(0.85)))
            }
            .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func chart(today: Date, latitude: Double, calendar: Calendar) -> some View {
        let series = Daylight.lengthSeries(from: start, to: max(goal, start), latitude: latitude, stepDays: 7, calendar: calendar)
        if series.count > 2 {
            let dark = colorScheme == .dark
            let hours = series.map(\.hours)
            let ticks = ChartMath.niceTicks(min: hours.min() ?? 0, max: hours.max() ?? 1, count: 3)
            let nowHours = Daylight.length(on: today, latitude: latitude, calendar: calendar) / 3600
            let inWindow = today >= start && today <= goal
            Chart {
                ForEach(series, id: \.date) { p in
                    LineMark(x: .value("Tag", p.date), y: .value("Stunden", p.hours))
                        .foregroundStyle(ChartPalette.fitness)
                        .lineStyle(ChartStyle.stroke(.main))
                        .interpolationMethod(.monotone)
                }
                if inWindow { HighlightPoint(x: .value("Tag", today), y: .value("Stunden", nowHours), color: ChartPalette.fitness, dark: dark) }
            }
            .chartXScale(domain: start...max(goal, start))
            .chartYScale(domain: (ticks.first ?? 0)...(ticks.last ?? 1))
            .chartStyleAxes(yTicks: ticks, yLabel: { "\(Int($0.rounded())) h" })
            .chartStyleHeight(110)
            .chartAccessibility(label: "Tageslicht vom Saisonstart bis zum Ziel",
                                value: "Heute \(Daylight.durationText(minutes: Int((nowHours * 60).rounded()))), am Ziel \(Daylight.durationText(minutes: Int(((series.last?.hours ?? 0) * 60).rounded())))")
        }
    }
}
