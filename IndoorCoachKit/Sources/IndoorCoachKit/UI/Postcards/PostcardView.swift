import SwiftUI

/// Postkarte einer Etappe (docs/22, B2). Feste Signatur `PostcardView(postcard:style:)` aus AP0: Album und Pager zeigen
/// `.full`, der Gipfelmoment `.compact` (antippbar → Album).
///
/// - Papierton `canvasLight` mit Tinte `#24131D` in beiden Erscheinungsbildern (die Karte ist ein Gegenstand, kein Hintergrund),
///   Text steht nie auf dem Himmel.
/// - Illustration, Briefmarke und Poststempel sind dekorativ; VoiceOver liest die Karte als ein Element.
/// - Beim Öffnen dreht sich die Karte einmal von der Rückseite auf die Vorderseite; bei „Bewegung reduzieren“ nur eine
///   Überblendung. Auf schmalen Breiten steht der Text unter dem Bild, ab etwa 520 pt Breite wird die Karte zum Querformat 3:2.
struct PostcardView: View {
    enum Style: Equatable {
        /// Kleine Fassung im Gipfelmoment, antippbar.
        case compact
        /// Große Fassung im Album.
        case full
    }

    var postcard: Postcard
    var style: Style
    /// „Dein Satz vom 4. November: …“, nur auf der Gardasee-Karte und nur mit gesetztem Warum (wörtlich, nur lokal).
    var whyAddendum: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double
    @State private var width: CGFloat = 0

    init(postcard: Postcard, style: Style, whyAddendum: String? = nil) {
        self.postcard = postcard
        self.style = style
        self.whyAddendum = whyAddendum
        // Volle, freigeschaltete Karten starten auf der Rückseite und drehen sich auf.
        _angle = State(initialValue: style == .full && postcard.unlocked ? 180 : 0)
    }

    static let paper = Color(Palette.canvasLight)
    private static let corner: CGFloat = 20

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
            .accessibilityIdentifier("postcard.view")
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .compact: compact
        case .full: full
        }
    }

    private var spokenLabel: String {
        var label = Postcards.accessibilityLabel(postcard)
        if let whyAddendum, Postcards.showsWhy(postcard) { label += " " + whyAddendum }
        return label
    }

    private var showsWhy: String? { Postcards.showsWhy(postcard) ? whyAddendum : nil }

    // MARK: Kompakt

    @ViewBuilder
    private var compact: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    PostcardIllustration(stage: postcard.stage).aspectRatio(3 / 2, contentMode: .fit)
                    compactCaption.padding(14)
                }
            } else {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        PostcardIllustration(stage: postcard.stage).frame(width: geo.size.width * 0.6)
                        VStack(alignment: .leading, spacing: 6) {
                            PostcardStamp(stage: postcard.stage, size: 44).frame(maxWidth: .infinity, alignment: .trailing)
                            if postcard.unlocked {
                                Text(Postcards.firstLine(postcard.text)).font(.caption2).foregroundStyle(Theme.ink.opacity(0.85))
                                    .lineLimit(3).minimumScaleFactor(0.85)
                            }
                            Spacer(minLength: 0)
                            compactCaption
                        }
                        .padding(10)
                        .frame(width: geo.size.width * 0.4, alignment: .leading)
                    }
                }
                .aspectRatio(3 / 2, contentMode: .fit)
            }
        }
        .background(Self.paper)
        .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .saturation(postcard.unlocked ? 1 : 0.2)
        .opacity(postcard.unlocked ? 1 : 0.55)
        .overlay(alignment: .bottomLeading) { if !postcard.unlocked { LockBadge().padding(10) } }
    }

    private var compactCaption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(postcard.place).font(.subheadline.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8)
            Text("\(Postcards.stampLabel(postcard)) · \(postcard.elevation) m").font(.caption).lineLimit(2).minimumScaleFactor(0.8)
            if dynamicTypeSize.isAccessibilitySize, postcard.unlocked {
                Text(Postcards.firstLine(postcard.text)).font(.caption).lineLimit(3)
            }
        }
        .foregroundStyle(Theme.ink)
    }

    // MARK: Voll

    private var full: some View {
        ZStack {
            front.opacity(angle <= 90 && !(reduceMotion && angle != 0) ? 1 : 0)
            back.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(angle > 90 && !reduceMotion ? 1 : 0)
        }
        .rotation3DEffect(.degrees(reduceMotion ? 0 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task {
            guard angle != 0 else { return }
            if reduceMotion {
                withAnimation(CelebrationMotion.animation(.smooth, reduceMotion: true)) { angle = 0 }
            } else {
                try? await Task.sleep(for: .milliseconds(40))
                withAnimation(CelebrationMotion.animation(.spring, reduceMotion: false)) { angle = 0 }
            }
        }
    }

    private var isWide: Bool { width >= 520 && !dynamicTypeSize.isAccessibilitySize }

    @ViewBuilder
    private var front: some View {
        Group {
            if isWide { wideFront } else { narrowFront }
        }
        .background(Self.paper)
        .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .foregroundStyle(Theme.ink)
    }

    private var narrowFront: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                art.aspectRatio(3 / 2, contentMode: .fit)
                PostcardStamp(stage: postcard.stage, size: 64).rotationEffect(.degrees(3)).padding(10)
            }
            VStack(alignment: .leading, spacing: 10) {
                heading
                message(of: postcard)
                footer
            }
            .padding(16)
        }
    }

    private var wideFront: some View {
        HStack(alignment: .top, spacing: 0) {
            art.frame(width: width * 0.6, height: width / 1.5)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    heading
                    Spacer(minLength: 8)
                    PostcardStamp(stage: postcard.stage, size: 64).rotationEffect(.degrees(3))
                }
                message(of: postcard)
                Spacer(minLength: 0)
                footer
            }
            .padding(16)
            .frame(width: width * 0.4, height: width / 1.5, alignment: .topLeading)
        }
    }

    /// Die Illustration; bei gesperrten Karten blass mit Schloss.
    private var art: some View {
        PostcardIllustration(stage: postcard.stage)
            .saturation(postcard.unlocked ? 1 : 0.15)
            .opacity(postcard.unlocked ? 1 : 0.5)
            .overlay { if !postcard.unlocked { LockBadge(size: 56) } }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Etappe \(postcard.stage) von \(WinterJourney.stages.count)").font(.caption.weight(.semibold)).textCase(.uppercase).tracking(0.8)
                .opacity(0.8)
            Text(postcard.place).font(.title2.weight(.bold))
            Text("\(postcard.elevation) m").font(.subheadline).opacity(0.8)
        }
    }

    @ViewBuilder
    private func message(of card: Postcard) -> some View {
        if card.unlocked {
            Text(card.text).font(.callout).fixedSize(horizontal: false, vertical: true)
            if let line = showsWhy {
                Text(line)
                    .font(.callout.italic())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        } else {
            Text(Postcards.lockedCaption(card)).font(.callout.weight(.semibold))
            Text("Diese Karte wartet an der nächsten Etappe auf dich.").font(.callout).opacity(0.85)
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            if postcard.unlocked { PostcardPostmark(place: postcard.place, date: Postcards.postmarkDate(postcard), stage: postcard.stage) }
            Spacer(minLength: 8)
            if postcard.unlocked {
                Text("Dein Coach").font(.system(.callout, design: .serif).italic())
            }
        }
    }

    private var back: some View {
        ZStack {
            Self.paper
            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    PostcardStamp(stage: postcard.stage, size: 72).rotationEffect(.degrees(3))
                }
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle().fill(Theme.ink.opacity(0.12)).frame(height: 1.5)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }
}

// MARK: - Bausteine

/// Briefmarke mit Perforation, Level-Symbol und „4/10“ (Tinte auf Sunset, ≥ 6,9:1).
struct PostcardStamp: View {
    var stage: Int
    var size: CGFloat
    @ScaledMetric(relativeTo: .body) private var scale = 1

    var body: some View {
        let side = size * min(scale, 1.6)
        let level = WinterArc.levels[min(WinterArc.levels.count, max(1, stage)) - 1]
        VStack(spacing: side * 0.04) {
            Image(systemName: level.symbol).font(.system(size: side * 0.3, weight: .semibold))
            Text("\(stage)/\(WinterJourney.stages.count)").font(.system(size: side * 0.17, weight: .heavy)).monospacedDigit()
        }
        .foregroundStyle(Theme.ink)
        .frame(width: side * 0.78, height: side * 0.92)
        .background(Theme.sunset, in: RoundedRectangle(cornerRadius: 2))
        .padding(side * 0.1)
        .background(PostcardView.paper, in: StampShape())
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

/// Rechteck mit halbrunden Perforationslöchern am Rand.
struct StampShape: Shape {
    func path(in rect: CGRect) -> Path {
        var holes = Path()
        let r: CGFloat = 2.6, step: CGFloat = 7.5
        var x = rect.minX + step / 2
        while x < rect.maxX {
            holes.addEllipse(in: CGRect(x: x - r, y: rect.minY - r, width: r * 2, height: r * 2))
            holes.addEllipse(in: CGRect(x: x - r, y: rect.maxY - r, width: r * 2, height: r * 2))
            x += step
        }
        var y = rect.minY + step / 2
        while y < rect.maxY {
            holes.addEllipse(in: CGRect(x: rect.minX - r, y: y - r, width: r * 2, height: r * 2))
            holes.addEllipse(in: CGRect(x: rect.maxX - r, y: y - r, width: r * 2, height: r * 2))
            y += step
        }
        return Path(rect).subtracting(holes)
    }
}

/// Runder Poststempel mit Ort und Ankunftsdatum („18. DEZ. 2026“); ohne Datum steht die Etappe darin.
struct PostcardPostmark: View {
    var place: String
    var date: String?
    var stage: Int
    @ScaledMetric private var diameter: CGFloat

    init(place: String, date: String?, stage: Int, diameter: CGFloat = 92) {
        self.place = place
        self.date = date
        self.stage = stage
        _diameter = ScaledMetric(wrappedValue: diameter, relativeTo: .caption)
    }

    var body: some View {
        let ink = Theme.ink.opacity(0.78)
        VStack(spacing: diameter * 0.02) {
            Text(place.uppercased()).font(.system(size: diameter * 0.115, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.5)
            Rectangle().frame(height: max(1, diameter * 0.012))
            Text(date ?? "ETAPPE \(stage)").font(.system(size: diameter * 0.11, weight: .bold)).lineLimit(2)
                .multilineTextAlignment(.center).minimumScaleFactor(0.6)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, diameter * 0.14)
        .frame(width: diameter, height: diameter)
        .overlay(Circle().stroke(ink, lineWidth: max(1.5, diameter * 0.022)))
        .overlay(Circle().stroke(ink, lineWidth: max(1, diameter * 0.011)).padding(diameter * 0.055))
        .rotationEffect(.degrees(-9))
        .accessibilityHidden(true)
    }
}

/// Schloss auf einer weißen Scheibe (Tinte auf Weiß) für noch nicht erreichte Karten.
struct LockBadge: View {
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.9), in: Circle())
            .accessibilityHidden(true)
    }
}
