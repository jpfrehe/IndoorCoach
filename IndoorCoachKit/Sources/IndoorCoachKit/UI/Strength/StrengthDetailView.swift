import Charts
import SwiftUI

/// Zeile im Verlauf für Kraft und „Andere Einheit“.
struct StrengthRow: View {
    var row: StoredStrengthSession

    var body: some View {
        let s = row.session
        HStack(spacing: 12) {
            Image(systemName: row.isOtherSport ? "figure.run" : "dumbbell.fill")
                .font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(StrengthFormat.title(row)).font(.headline)
                Text("\(row.start.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute().locale(Locale.de))) · \(Formatters.duration(s.durationSeconds))")
                    .font(.caption).foregroundStyle(Theme.rowSecondary)
            }
            Spacer(minLength: 0)
            Text(loadText(s)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.rowSecondary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.strength.row")
    }

    private func loadText(_ s: StrengthSession) -> String {
        if let load = MuscleLoad.load(of: s) { return "Last \(Int(load.rounded()))" }
        return "Härte fehlt"
    }
}

/// Detail einer Kraft- oder anderen Einheit: Dauer, Pulsverlauf (falls aufgezeichnet), Übungen, Härte × min, Beine, Quelle.
struct StrengthDetailView: View {
    var row: StoredStrengthSession
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        let s = row.session
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Überblick", systemImage: row.isOtherSport ? "figure.run" : "dumbbell") {
                    VStack(alignment: .leading, spacing: 8) {
                        fact("Beginn", row.start.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale.de)))
                        fact("Dauer", Formatters.duration(s.durationSeconds))
                        fact("Härte", StrengthFormat.exertionText(s.validExertion))
                        fact("Muskel-Last", loadText(s))
                        if showsLegs { fact("Beine", s.effectiveLegShare.label) }
                        fact("Quelle", StrengthFormat.sourceLabel(row.source))
                    }
                }
                if let note = row.healthNote {
                    Label(note, systemImage: "heart.text.square")
                        .font(.caption).foregroundStyle(Theme.rowSecondary)
                        .accessibilityIdentifier("strength.detail.healthNote")
                }
                if let hr = row.heartRateSeries, hr.contains(where: { $0 > 0 }) { heartRateCard(hr) }
                if let heart = model.heartZoneTime(for: row)?.heart { zonesCard(heart) }
                if !s.exercises.isEmpty { exercisesCard(s.exercises) }
                if !s.note.isEmpty {
                    Card(title: "Notiz", systemImage: "note.text") { Text(s.note).font(.body) }
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Text("Einheit löschen").frame(maxWidth: .infinity, minHeight: 48)
                }
                .accessibilityIdentifier("strength.detail.delete")
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle(StrengthFormat.title(row))
        .inlineNavigationTitle()
        .confirmationDialog("Einheit löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { model.deleteStrength(row); dismiss() }
        } message: {
            Text("Die Einheit verschwindet aus Verlauf und Muskel-Last.")
        }
    }

    private var showsLegs: Bool { row.feedsMuscleTrack }

    private func loadText(_ s: StrengthSession) -> String {
        guard let load = MuscleLoad.load(of: s), let e = s.validExertion else { return "fehlt (Härte angeben)" }
        return "\(Int(load.rounded())) (\(e) × \(Int(s.durationMinutes.rounded())) min)"
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Theme.rowSecondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func heartRateCard(_ hr: [UInt8]) -> some View {
        // Höchstens ~300 Punkte zeichnen; Lücken (0) bleiben leer.
        let step = max(1, hr.count / 300)
        let points = stride(from: 0, to: hr.count, by: step).compactMap { i -> (Double, Int)? in
            hr[i] > 0 ? (Double(i) / 60, Int(hr[i])) : nil
        }
        let valid = hr.filter { $0 > 0 }.map(Int.init)
        let avg = valid.reduce(0, +) / max(1, valid.count)
        return Card(title: "Puls", systemImage: "heart.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ø \(avg) · max \(valid.max() ?? 0) bpm").font(.subheadline.monospacedDigit())
                Chart(points, id: \.0) { p in
                    LineMark(x: .value("Minute", p.0), y: .value("bpm", p.1))
                        .foregroundStyle(Theme.accent)
                }
                .chartXAxisLabel("min")
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 150)
                .accessibilityLabel("Pulsverlauf, Durchschnitt \(avg), Maximum \(valid.max() ?? 0) Schläge pro Minute")
            }
        }
    }

    private func zonesCard(_ heart: [Int]) -> some View {
        Card(title: "Zeit in Pulszonen", systemImage: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<min(5, heart.count), id: \.self) { i in
                    HStack {
                        Text("Zone \(i + 1) \(HeartRateZones.names[i])").font(.subheadline)
                        Spacer()
                        Text("\(Int((Double(heart[i]) / 60).rounded())) min").font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("strength.detail.zones")
    }

    private func exercisesCard(_ exercises: [PerformedExercise]) -> some View {
        Card(title: "Übungen", systemImage: "list.bullet") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(exercises) { e in
                    HStack {
                        Image(systemName: e.isPerformed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(e.isPerformed ? Theme.accent : Theme.rowSecondary)
                        Text(StrengthFormat.exerciseName(e.exerciseID))
                        Spacer()
                        if let v = StrengthFormat.volume(e) { Text(v).font(.caption).foregroundStyle(Theme.rowSecondary) }
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
