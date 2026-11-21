import SwiftUI

/// Postkarte einer Etappe (docs/22, B2). AP0: Stub mit fester Signatur `PostcardView(postcard:style:)`; Agent B
/// zeichnet Illustration, Briefmarke, Poststempel und Drehung. Genutzt von Album (`.full`) und Gipfelmoment (`.compact`).
struct PostcardView: View {
    enum Style: Equatable {
        /// Kleine Fassung im Gipfelmoment, antippbar.
        case compact
        /// Große Fassung im Album.
        case full
    }

    var postcard: Postcard
    var style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Etappe \(postcard.stage) von \(WinterJourney.stages.count): \(postcard.place)")
                .font(style == .full ? .headline : .subheadline.weight(.semibold))
            if style == .full || postcard.unlocked { Text(postcard.text).font(.callout) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(postcard.unlocked ? 1 : 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("postcard.view")
    }
}
