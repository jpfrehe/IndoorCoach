import SwiftData
import SwiftUI

/// Album der Postkarten (docs/22, B2): „Deine Postkarten · 4 von 10“ im Winter-Arc-Hub unter der Winter-Reise. Nicht erreichte
/// Karten sind gedimmt mit Schloss, die nächste nennt „Noch 38 % bis Bormio“ (Goal Gradient). Ein Tipp öffnet die Karte groß,
/// mit Wischen zur nächsten und Teilen als Bild (1500 × 1000, ohne Werte).
struct PostcardAlbumCard: View {
    var status: WinterArc.Status
    var rides: [RideSummary]
    @Environment(AppModel.self) private var model
    @State private var opened: Opened?

    struct Opened: Identifiable { var stage: Int; var id: Int { stage } }

    var body: some View {
        let cards = model.postcards(rides: rides, status: status)
        Card(title: Postcards.albumTitle(cards), systemImage: "envelope") {
            Text(Postcards.albumSubtitle(cards)).font(.subheadline).foregroundStyle(Theme.rowSecondary)
            PostcardAlbumView(cards: cards) { opened = Opened(stage: $0) }
        }
        .accessibilityElement(children: .contain)
        .sheet(item: $opened) { item in
            PostcardPager(cards: cards, start: item.stage,
                          whyAddendum: Postcards.whyAddendum(note: model.whyNote, savedOn: model.whyNoteSavedOn))
        }
    }
}

/// Das Raster: zwei Spalten, bei großer Schrift eine.
struct PostcardAlbumView: View {
    var cards: [Postcard]
    var onSelect: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                  spacing: 14) {
            ForEach(cards) { card in tile(card) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("postcard.album")
    }

    private func tile(_ card: Postcard) -> some View {
        Button { onSelect(card.stage) } label: {
            VStack(alignment: .leading, spacing: 6) {
                PostcardIllustration(stage: card.stage)
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .saturation(card.unlocked ? 1 : 0.15)
                    .opacity(card.unlocked ? 1 : 0.5)
                    .overlay(alignment: .bottomTrailing) { if !card.unlocked { LockBadge().padding(8) } }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(card.unlocked ? 0.14 : 0), radius: 5, y: 2)
                Text("\(card.stage) · \(card.place)").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(caption(card)).font(.caption).foregroundStyle(Theme.rowSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Postcards.shortAccessibilityLabel(card))
        .accessibilityHint("Öffnet die Karte")
        .accessibilityIdentifier("postcard.tile.\(card.stage)")
    }

    private func caption(_ card: Postcard) -> String {
        guard card.unlocked else { return Postcards.lockedCaption(card) }
        if let arrived = card.arrivedOn {
            return "Angekommen am " + arrived.formatted(.dateTime.day().month(.abbreviated).locale(Locale.de))
        }
        return "\(card.elevation) m"
    }
}

/// Die Seite hinter dem Link „Postkarten“ in der Winter-Reise (rechnet selbst, damit der Link nur zwei Zeilen braucht).
struct PostcardAlbumScreen: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \StoredRide.startDate) private var storedRides: [StoredRide]

    var body: some View {
        let rides = storedRides.map(\.summary)
        ScrollView {
            if let status = model.winterArc(rides: rides) {
                PostcardAlbumCard(status: status, rides: rides).padding()
            }
        }
        .background(Theme.canvas)
        .navigationTitle("Postkarten")
        .inlineNavigationTitle()
    }
}

// MARK: - Pager

/// Die Karte groß, mit Wischen zur nächsten; „Fertig“ schließt. Kein Element verschwindet von selbst.
struct PostcardPager: View {
    var cards: [Postcard]
    var whyAddendum: String?
    @State private var selection: Int
    @Environment(\.dismiss) private var dismiss

    init(cards: [Postcard], start: Int, whyAddendum: String?) {
        self.cards = cards
        self.whyAddendum = whyAddendum
        _selection = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(cards) { card in
                    ScrollView {
                        VStack(spacing: 16) {
                            PostcardView(postcard: card, style: .full, whyAddendum: whyAddendum)
                            PostcardShareButton(card: card, active: selection == card.stage)
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 48)
                    }
                    .tag(card.stage)
                }
            }
            .pagedStyle()
            .background(Theme.canvas)
            .navigationTitle("Postkarten")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }.accessibilityIdentifier("postcard.done")
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: selection)
        }
        .presentationDetents([.large])
    }
}

private extension View {
    @ViewBuilder
    func pagedStyle() -> some View {
        #if os(iOS)
        tabViewStyle(.page(indexDisplayMode: .always))
        #else
        self
        #endif
    }
}

// MARK: - Teilen

/// Das System-Teilen-Menü mit dem Kartenbild; erst nach dem Tipp verlässt etwas das Gerät. Gesperrte Karten lassen sich nicht teilen.
struct PostcardShareButton: View {
    var card: Postcard
    /// Nur die gerade sichtbare Seite rendert das Bild (1500 × 1000 ist nicht billig).
    var active: Bool
    @State private var rendered: ShareImageRenderer.Rendered?

    var body: some View {
        Group {
            if card.unlocked {
                if let rendered {
                    ShareLink(item: rendered.url, message: Text(Postcards.shareText(for: card)),
                              preview: SharePreview("\(card.place) · Etappe \(card.stage)", image: rendered.preview)) {
                        Label("Postkarte teilen", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(JellyButtonStyle())
                    .accessibilityHint("Öffnet das Teilen-Menü mit dem Bild der Karte, ohne Werte")
                    .accessibilityIdentifier("postcard.share")
                } else {
                    Button {} label: {
                        HStack(spacing: 8) { ProgressView(); Text("Bild wird erstellt …") }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(JellyButtonStyle())
                    .disabled(true)
                    .accessibilityIdentifier("postcard.share")
                }
            }
        }
        .task(id: active ? card : nil) {
            guard active, card.unlocked else { return }
            rendered = PostcardShareRenderer.render(card)
        }
    }
}

/// Das geteilte Bild: 1500 × 1000, Illustration links, Briefmarke, Poststempel und Text rechts. Reine Wert-View ohne Umgebung
/// (wird von `ImageRenderer` gezeichnet). Keine Watt-, Puls- oder Dienstnamen, nur das Logo klein unten.
struct PostcardShareCard: View {
    static let size = CGSize(width: 1500, height: 1000)
    var card: Postcard

    var body: some View {
        HStack(spacing: 0) {
            PostcardIllustration(stage: card.stage).frame(width: 900, height: 1000)
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ETAPPE \(card.stage) VON \(WinterJourney.stages.count)")
                            .font(.system(size: 28, weight: .semibold)).tracking(3)
                        Text(card.place).font(.system(size: 64, weight: .bold)).lineLimit(2).minimumScaleFactor(0.6)
                        Text("\(card.elevation) m").font(.system(size: 34, weight: .medium))
                    }
                    Spacer(minLength: 12)
                    PostcardStamp(stage: card.stage, size: 150)
                }
                Text(card.text).font(.system(size: 36)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    PostcardPostmark(place: card.place, date: Postcards.postmarkDate(card), stage: card.stage, diameter: 180)
                    Spacer(minLength: 8)
                    Text("Dein Coach").font(.system(size: 34, design: .serif).italic())
                }
                Text("IndoorCoach").font(.system(size: 28, weight: .bold)).tracking(2).opacity(0.8)
            }
            .padding(44)
            .frame(width: 600, height: 1000, alignment: .topLeading)
        }
        .foregroundStyle(Theme.ink)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(PostcardView.paper)
        .environment(\.colorScheme, .light)
    }
}

enum PostcardShareRenderer {
    @MainActor
    static func render(_ card: Postcard) -> ShareImageRenderer.Rendered? {
        ShareImageRenderer.render(PostcardShareCard(card: card), size: PostcardShareCard.size, filename: filename(for: card))
    }

    /// „IndoorCoach-Postkarte-4-Stilfser-Joch.png“ (keine Leerzeichen, keine Schrägstriche).
    static func filename(for card: Postcard) -> String {
        let place = card.place.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-")
        return "IndoorCoach-Postkarte-\(card.stage)-\(place).png"
    }
}
