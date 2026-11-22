import SwiftUI

/// Die Feier nach der Fahrt (docs/22, B1): Vollbild ohne Zeitlimit, ruhig, mit klarem „Weiter“ und „Schließen“. Der Text
/// steht nie direkt auf dem Himmel, sondern als Tinte auf Sunset oder auf weißen Karten; deshalb bleibt die Feier auch im
/// Dunkelmodus gleich lesbar (Farbschema fest hell, wie die Teilen-Bilder). Inhalte stehen in einer `ScrollView`.
struct MomentSheet: View {
    var presentation: MomentPresentation

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var circleSize: CGFloat = 160
    @State private var appeared = false
    @State private var textVisible = false
    @State private var showValues = false
    /// Der Profilname steht nur auf dem Bild, wenn der Nutzer ihn einschaltet.
    @State private var showName = false
    @State private var shared: ShareImageRenderer.Rendered?
    @AccessibilityFocusState private var headlineFocused: Bool

    private static let fallback = Moment(id: "", kind: .levelUp, date: .now, headline: "Gipfelmoment")
    private var main: Moment { presentation.batch.headline ?? Self.fallback }
    private var others: [Moment] { Array(presentation.batch.moments.dropFirst()) }
    private var largeText: Bool { typeSize.isAccessibilitySize }

    /// Der Schalter lohnt nur, wenn das Bild mit Werten anders aussieht.
    private var hasValues: Bool {
        ShareText.headline(for: main, showValues: true) != ShareText.headline(for: main, showValues: false)
            || ShareText.detail(for: main, showValues: true) != ShareText.detail(for: main, showValues: false)
    }

    var body: some View {
        ZStack {
            CelebrationBackdrop(skyProgress: presentation.skyProgress,
                                animated: CelebrationMotion.allowsParticleMotion(reduceMotion: reduceMotion))
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 20) {
                        content
                        if largeText { actions } // bei großer Schrift mit dem Inhalt scrollen statt den Platz zu fressen
                    }
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
                if !largeText { actions.padding(.horizontal, 20).padding(.bottom, 8).frame(maxWidth: 680) }
            }
        }
        .foregroundStyle(Theme.ink)
        .environment(\.colorScheme, .light)
        .sensoryFeedback(.success, trigger: appeared)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("moment.sheet")
        .task { await enter() }
        .task(id: ShareKey(values: showValues, name: showName)) { await renderShareImage() }
    }

    // MARK: Teile

    private var topBar: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.85), in: Circle())
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("Schließen")
            .accessibilityIdentifier("moment.close")
            headerText
                .frame(maxWidth: .infinity, minHeight: 44)
            Color.clear.frame(width: 44, height: 44) // hält die Zeile mittig
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    /// Bis zur normalen Größe „GIPFELMOMENT · Datum“ in Großbuchstaben mit Laufweite; bei großer Schrift normale Schreibung in
    /// zwei Zeilen, ohne Trennung mitten im Wort.
    @ViewBuilder private var headerText: some View {
        let label = "Gipfelmoment, \(presentation.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale.de)))"
        if largeText {
            VStack(spacing: 2) {
                Text("Gipfelmoment").font(.caption.weight(.bold))
                Text(MomentStyle.dateText(presentation.date)).font(.caption)
            }
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
        } else {
            Text("GIPFELMOMENT · \(MomentStyle.dateText(presentation.date))")
                .font(.caption.weight(.bold)).tracking(1.5)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(label)
        }
    }

    private var content: some View {
        VStack(spacing: 18) {
            Image(systemName: MomentStyle.symbol(for: main))
                .font(.system(size: min(circleSize, 220) * 0.5, weight: .semibold))
                .frame(width: min(circleSize, 220), height: min(circleSize, 220))
                .background(Color.white.opacity(0.55), in: Circle())
                .scaleEffect(reduceMotion || appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                if let greeting = presentation.greeting {
                    Text(greeting).font(.title3.weight(.semibold))
                }
                Text(main.headline)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headlineFocused)
                    .accessibilityIdentifier("moment.headline")
                if let detail = main.detail {
                    Text(detail).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let chip = MomentStyle.sourceChip(for: main) {
                    Label(chip, systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.white.opacity(0.85), in: Capsule())
                }
            }
            .opacity(textVisible ? 1 : 0)

            Group {
                if let postcard = presentation.postcard { PostcardView(postcard: postcard, style: .compact) }
                if !others.isEmpty { subMoments }
                if let note = presentation.coachNote { coachCard(note) }
                if let why = presentation.whyQuote { whyCard(why) }
            }
            .opacity(textVisible ? 1 : 0)
        }
    }

    private var subMoments: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(others) { moment in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: MomentStyle.symbol(for: moment)).font(.title3).frame(width: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(moment.headline).font(.subheadline.weight(.semibold))
                        if let detail = moment.detail { Text(detail).font(.caption).foregroundStyle(Theme.rowSecondary) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func coachCard(_ note: CoachNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Dein Coach", systemImage: "quote.bubble").font(.caption.weight(.bold)).foregroundStyle(Theme.rowSecondary)
            Text(note.text).font(.body).fixedSize(horizontal: false, vertical: true)
            Text(note.source).font(.caption).foregroundStyle(Theme.rowSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("moment.coachNote")
    }

    private func whyCard(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Du hast geschrieben:").font(.caption.weight(.bold)).foregroundStyle(Theme.rowSecondary)
            Text("„\(why)“").font(.body.italic()).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if presentation.isExample {
                Text("Beispiel mit Demo-Daten").font(.caption.weight(.semibold)).accessibilityIdentifier("moment.example")
            }
            Button { dismiss() } label: { Text("Weiter").frame(maxWidth: .infinity) }
                .buttonStyle(.jelly)
                .accessibilityIdentifier("moment.continue")
            shareButton
            if hasValues {
                Toggle("Werte auf dem Bild zeigen", isOn: $showValues)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("moment.values")
            }
            if presentation.shareName != nil {
                Toggle("Namen zeigen", isOn: $showName)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("moment.name")
            }
            if !largeText {
                Text(showName ? "Auf dem Bild steht dein Name aus dem Profil, aber keine Dienstnamen."
                     : "Auf dem Bild stehen keine Dienstnamen.")
                    .font(.caption).foregroundStyle(Theme.rowSecondary).multilineTextAlignment(.center)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .padding(16)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder private var shareButton: some View {
        if let shared {
            ShareLink(item: shared.url, message: Text(ShareText.caption(for: main, showValues: showValues)),
                      preview: SharePreview("Gipfelmoment", image: shared.preview)) {
                Label("Als Bild teilen", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.soft)
            .accessibilityIdentifier("moment.share")
            .accessibilityHint("Öffnet das Teilen-Menü mit deinem Gipfelmoment-Bild")
        } else {
            Button {} label: {
                HStack(spacing: 8) { ProgressView(); Text("Bild wird erstellt …") }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.soft)
            .disabled(true)
            .accessibilityIdentifier("moment.share")
        }
    }

    // MARK: Ablauf

    /// Kreis springt auf (Spring), Text blendet 0,15 s später ein, einmal Haptik; bei „Bewegung reduzieren“ nur eine
    /// Überblendung. Danach bekommt die Überschrift den VoiceOver-Fokus.
    private func enter() async {
        if reduceMotion {
            withAnimation(CelebrationMotion.reducedFade) { appeared = true; textVisible = true }
        } else {
            withAnimation(CelebrationMotion.animation(.spring, reduceMotion: false)) { appeared = true }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(CelebrationMotion.animation(.smooth, reduceMotion: false)) { textVisible = true }
        }
        try? await Task.sleep(for: .milliseconds(500))
        headlineFocused = true
    }

    private struct ShareKey: Hashable {
        var values: Bool
        var name: Bool
    }

    /// Das Teilen-Bild entsteht erst nach der Eingangsanimation (~0,7 s) und nach jeder Änderung der Schalter neu; ein
    /// schnelles Umschalten rendert nur einmal. Bis dahin zeigt die Karte „Bild wird erstellt …“.
    private func renderShareImage() async {
        shared = nil
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        let card = MomentShareCard(headline: ShareText.headline(for: main, showValues: showValues),
                                   detail: ShareText.detail(for: main, showValues: showValues),
                                   symbol: MomentStyle.symbol(for: main), dateText: MomentStyle.dateText(presentation.date),
                                   name: ShareText.shareName(presentation.shareName, show: showName), skyProgress: presentation.skyProgress)
        shared = ShareImageRenderer.render(card, size: MomentShareCard.size, filename: "IndoorCoach-Gipfelmoment.png")
    }
}

/// Ein gezeigter Stapel samt Aufbereitung (Träger für `fullScreenCover(item:)`).
struct PresentedMoment: Identifiable {
    let id = UUID()
    var presentation: MomentPresentation
}
