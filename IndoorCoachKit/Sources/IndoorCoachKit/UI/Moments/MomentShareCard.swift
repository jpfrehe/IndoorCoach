import SwiftUI

/// Kleine Helfer der Moment-Oberfläche: Symbol je Art und das Datum der Überschriftzeile.
enum MomentStyle {
    static func symbol(for moment: Moment) -> String {
        switch moment.kind {
        case .levelUp:
            let n = ShareText.levelNumber(of: moment) ?? 1
            return WinterArc.levels[min(WinterArc.levels.count, max(1, n)) - 1].symbol
        case .record: return "trophy"
        case .ftpRise: return "bolt.fill"
        case .challengeCompleted: return "flag.checkered"
        case .comeback: return "figure.indoor.cycle"
        case .streak: return "flame"
        case .firstRide: return "snowflake"
        case .weekPlanDone: return "checkmark.seal"
        case .strengthTier: return "dumbbell"
        case .secondData: return "waveform.path.ecg"
        }
    }

    /// „Do., 18. Dez.“
    static func dateText(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale.de
        f.timeZone = calendar.timeZone
        f.dateFormat = "E, d. MMM"
        return f.string(from: date)
    }

    /// Wo die Zahl herkommt (kleiner Chip unter der Bestleistung); nil bei Momenten ohne Messwert.
    static func sourceChip(for moment: Moment) -> String? {
        switch moment.kind {
        case .record: "gemessen · Sekundendaten"
        case .ftpRise: "geschätzt · Sekundendaten"
        default: nil
        }
    }
}

/// Das Bild für „Als Bild teilen“: 1080 × 1920 px (Story-Format), Himmel und Sunset, Symbol, Überschrift, Unterzeile, Datum
/// und „IndoorCoach“ klein. Ohne Dienstnamen, ohne Fahrtnamen, Werte nur mit dem Schalter (das entscheidet `ShareText`
/// vor dem Aufruf), der Name nur, wenn er im Profil steht. Reine Werte ohne Umgebung, damit `ImageRenderer` es überall
/// zeichnen kann.
struct MomentShareCard: View {
    static let size = CGSize(width: 1080, height: 1920)

    var headline: String
    var detail: String?
    var symbol: String
    var dateText: String
    var name: String?
    var skyProgress: Double

    var body: some View {
        ZStack {
            LinearGradient(colors: WinterSky.stops(progress: skyProgress).map { Color($0) }, startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Theme.sunset).opacity(0.85)
            Canvas { context, size in
                CelebrationParticles.draw(context, size: size, at: CelebrationParticles.duration, particles: CelebrationParticles.make())
            }
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Text("GIPFELMOMENT").font(.system(size: 40, weight: .heavy)).tracking(6)
                    Text(dateText).font(.system(size: 40, weight: .semibold))
                }
                .padding(.top, 140)

                Spacer(minLength: 40)

                VStack(spacing: 44) {
                    Image(systemName: symbol)
                        .font(.system(size: 210, weight: .semibold))
                        .frame(width: 460, height: 460)
                        .background(Color.white.opacity(0.55), in: Circle())
                    Text(headline)
                        .font(.system(size: 92, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.5)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 50, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)
                    }
                    if let name {
                        Text(name).font(.system(size: 54, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                .padding(.horizontal, 84)

                Spacer(minLength: 40)

                Text("IndoorCoach")
                    .font(.system(size: 36, weight: .bold)).tracking(2)
                    .padding(.bottom, 110)
            }
            .foregroundStyle(Theme.ink)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .light)
    }
}
