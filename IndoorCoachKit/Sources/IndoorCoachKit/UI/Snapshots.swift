import SwiftData
import SwiftUI

/// Static, platform-view-free compositions of the main screens. Used by the macOS snapshot tool
/// (ImageRenderer cannot draw List/ScrollView) to review the design without a simulator.
@MainActor
public enum SnapshotScenes {
    public struct Scene {
        public let name: String
        public let view: AnyView
    }

    public static func scenes(model: AppModel, container: ModelContainer) -> [Scene] {
        let rides = model.allRides()
        let workouts = (try? model.context.fetch(FetchDescriptor<StoredWorkout>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let detail = workouts.first { $0.type == .sweetSpot || $0.type == .vo2max } ?? workouts.first

        func phone<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> AnyView {
            AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.largeTitle.weight(.bold)).padding(.top, 8)
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(width: 393, alignment: .top)
                .environment(model)
                .modelContainer(container)
                .tint(Theme.accent)
            )
        }

        var result: [Scene] = [
            Scene(name: "01-heute", view: phone("Heute") {
                TodayDashboard(rides: rides, workouts: workouts, tab: .constant(.today))
            })
        ]
        if let detail {
            result.append(Scene(name: "02-workout", view: phone("") {
                WorkoutDetailContent(workout: detail, zwoURL: URL(fileURLWithPath: "/tmp/x.zwo"), onCalendar: {})
            }))
        }
        result.append(Scene(name: "03-plan", view: phone("Plan") {
            Card(title: "Diese & nächste Woche", systemImage: "calendar") {
                ForEach(workouts.filter { $0.date >= Calendar.current.startOfDay(for: .now) }) { w in
                    WorkoutRow(workout: w, ftp: model.profile.ftp)
                    Divider()
                }
            }
        }))
        result.append(Scene(name: "04-verlauf", view: phone("Verlauf") {
            Card { HistoryChart(rides: rides, ftp: model.profile.ftp, thresholdHeartRate: model.profile.thresholdHeartRate) }
            Card(title: "Letzte Fahrten", systemImage: "bicycle") {
                ForEach(rides.suffix(6).reversed()) { r in
                    RideRow(ride: r, ftp: model.profile.ftp, thresholdHeartRate: model.profile.thresholdHeartRate)
                    Divider()
                }
            }
        }))
        return result
    }

    /// App icon: indoor cyclist on the accent gradient with a rising power profile.
    public static var appIcon: some View {
        ZStack {
            // Sunset Jelly: peach → coral → jelly pink, ink glyph (same rules as the in-app primary buttons).
            LinearGradient(colors: [Color(Palette.peachFizz), Color(Palette.warmCoral), Color(Palette.jellyPink)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(alignment: .bottom, spacing: 28) {
                ForEach([0.30, 0.45, 0.38, 0.62, 0.50, 0.78], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 30).fill(Color(Palette.mangoPop).opacity(0.35)).frame(width: 92, height: 1024 * h * 0.62)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            Image(systemName: "figure.indoor.cycle")
                .font(.system(size: 520, weight: .semibold))
                .foregroundStyle(Color(Palette.ink))
                .offset(y: -40)
        }
        .frame(width: 1024, height: 1024)
    }
}
