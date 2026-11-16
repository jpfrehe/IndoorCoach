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
            Card { HistoryChart(rides: rides, ftp: model.profile.ftp) }
            Card(title: "Letzte Fahrten", systemImage: "bicycle") {
                ForEach(rides.suffix(6).reversed()) { r in
                    RideRow(ride: r, ftp: model.profile.ftp)
                    Divider()
                }
            }
        }))
        return result
    }

    /// App icon: indoor cyclist on the accent gradient with a rising power profile.
    public static var appIcon: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 1.0, green: 0.50, blue: 0.20), Color(red: 0.90, green: 0.20, blue: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(alignment: .bottom, spacing: 28) {
                ForEach([0.30, 0.45, 0.38, 0.62, 0.50, 0.78], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.22)).frame(width: 92, height: 1024 * h * 0.62)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 0)
            Image(systemName: "figure.indoor.cycle")
                .font(.system(size: 520, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
                .offset(y: -40)
        }
        .frame(width: 1024, height: 1024)
    }
}
