import SwiftData
import SwiftUI

/// "KW 47 · 16.–22. Nov."
enum WeekLabel {
    static func text(for weekStart: Date) -> String {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let week = calendar.component(.weekOfYear, from: weekStart)
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let locale = Locale(identifier: "de_DE")
        let from = weekStart.formatted(.dateTime.day().locale(locale))
        let to = end.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        return "KW \(week) · \(from).–\(to)"
    }
}

/// Highlight card on Heute (Sunday 16:00 through Tuesday): the headline and sentences of the finished week.
struct WeeklyReviewCard: View {
    var weekStart: Date
    var rides: [RideSummary]
    var workouts: [StoredWorkout]
    @Environment(AppModel.self) private var model
    @State private var hidden = false

    var body: some View {
        if !hidden, let review = model.weeklyReviews(rides: rides, workouts: workouts, focus: weekStart, count: 1).first {
            NavigationLink {
                WeeklyReviewView(focus: weekStart)
            } label: {
                // Short title: the close button sits in the card's corner (audit 2, A2-04 – "Ausblenden" used to
                // float detached below the card).
                Card(title: "Deine Woche", systemImage: "calendar.badge.checkmark") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(WeekLabel.text(for: weekStart)).font(.caption).foregroundStyle(Theme.rowSecondary)
                        Text(review.headline).font(.title3.weight(.bold)).foregroundStyle(.primary)
                        ForEach(review.sentences, id: \.self) { sentence in
                            Text(sentence).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("Alle Details ansehen")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("weeklyReview.card")
            .overlay(alignment: .topTrailing) {
                Button {
                    model.dismissWeeklyReview(weekStart)
                    withAnimation { hidden = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.rowSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(4)
                .accessibilityLabel("Ausblenden")
                .accessibilityIdentifier("weeklyReview.dismiss")
                .accessibilityHint("Blendet den Rückblick dieser Woche auf Heute aus")
            }
        }
    }
}

/// This week (or the one the card pointed at) plus the eight weeks before it.
struct WeeklyReviewView: View {
    var focus: Date = WeeklyReview.weekStart(containing: .now)
    @Environment(AppModel.self) private var model
    @Query(sort: \StoredRide.startDate) private var storedRides: [StoredRide]
    @Query(sort: \StoredWorkout.date) private var workouts: [StoredWorkout]

    var body: some View {
        let rides = storedRides.map(\.summary)
        let reviews = model.weeklyReviews(rides: rides, workouts: workouts, focus: focus, count: 9)
        ScrollView {
            VStack(spacing: 16) {
                if let current = reviews.first {
                    WeeklyReviewDetailCard(review: current, ftp: model.profile.ftp, prominent: true)
                }
                if reviews.count > 1 {
                    Text("Frühere Wochen")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(reviews.dropFirst()) { WeeklyReviewDetailCard(review: $0, ftp: model.profile.ftp, prominent: false) }
                }
                Text("Quellen: deine Fahrten (Strava, MyWhoosh, FIT-Import) und dein Plan in IndoorCoach. TSS aus Leistung und FTP, Relative Effort wie auf der Verlaufsseite.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("Wochenrückblick")
        .accessibilityIdentifier("weeklyReview.view")
    }
}

private struct WeeklyReviewDetailCard: View {
    var review: WeeklyReview
    var ftp: Int
    var prominent: Bool

    var body: some View {
        Card(title: WeekLabel.text(for: review.weekStart), systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 10) {
                Text(review.headline)
                    .font(prominent ? .title3.weight(.bold) : .headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(review.sentences, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                if !review.isEmpty {
                    HStack(alignment: .top) {
                        StatTile(title: "Fahrten", value: "\(review.rideCount)")
                        StatTile(title: "Zeit", value: Formatters.duration(Int((review.hours * 3600).rounded())))
                        StatTile(title: review.plannedTSS > 0 ? "TSS (Plan \(Int(review.plannedTSS.rounded())))" : "TSS",
                                 value: "\(Int(review.actualTSS.rounded()))")
                    }
                    if prominent {
                        HStack(alignment: .top) {
                            if let adherence = review.adherence {
                                StatTile(title: "Plan-Treue", value: "\(review.doneCount) von \(review.plannedCount)",
                                         unit: "· \(Int((adherence * 100).rounded())) %")
                            }
                            if let change = review.fitnessChange {
                                StatTile(title: "Fitness", value: WeeklyReview.signed(change, digits: 1), dot: Theme.fitness)
                            }
                            if let form = review.form {
                                StatTile(title: "Form", value: WeeklyReview.signed(form, digits: 0))
                            }
                        }
                        if review.effortTotal > 0 {
                            Text(effortLine).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private var effortLine: String {
        var text = "Relative Effort \(Formatters.decimal(review.effortTotal))"
        if let range = review.effortRange {
            text += " · üblicher Bereich \(Int(range.lower.rounded()))–\(Int(range.upper.rounded()))"
        }
        return text
    }
}
