import ActivityKit
import IndoorCoachKit
import SwiftUI
import WidgetKit

private extension Color {
    init(_ rgb: Palette.RGB) { self.init(red: rgb.r, green: rgb.g, blue: rgb.b) }
}

/// Sperrbildschirm und Dynamic Island werden immer auf dunklem Grund gezeichnet (Sunset-Jelly-Töne mit Kontrast).
private enum Style {
    static let surface = Color(Palette.ink)
    static let heart = Color(Palette.jellyPink)
    static let warning = Color(Palette.mangoPop)
    static let accent = Color(Palette.peachFizz)
}

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            LockScreenView(title: context.attributes.title, display: RecordingLiveDisplay(context.state))
                .activityBackgroundTint(Style.surface)
                .activitySystemActionForegroundColor(Style.accent)
        } dynamicIsland: { context in
            let display = RecordingLiveDisplay(context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HeartRateView(display: display, size: .title)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedView(startedAt: context.state.startedAt).font(.title2.monospacedDigit().weight(.semibold))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        BlockView(display: display)
                        WarningView(display: display)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: display.connectionWarning == nil ? "heart.fill" : "heart.slash.fill")
                    .foregroundStyle(display.connectionWarning == nil ? Style.heart : Style.warning)
                    .accessibilityHidden(true)
            } compactTrailing: {
                Text(display.heartRateText).font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(.white)
                    .accessibilityLabel(display.hasHeartRate ? "Puls \(display.heartRateText)" : "Kein Pulswert")
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(Style.heart)
                    .accessibilityLabel(display.accessibilityLabel(at: .now))
            }
            .keylineTint(Style.heart)
        }
    }
}

private struct LockScreenView: View {
    let title: String
    let display: RecordingLiveDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: display.kindSymbol).font(.headline).lineLimit(1)
                Spacer()
                ElapsedView(startedAt: display.state.startedAt).font(.title3.monospacedDigit().weight(.semibold))
            }
            HStack(alignment: .firstTextBaseline) {
                HeartRateView(display: display, size: .largeTitle)
                Spacer()
                WarningView(display: display)
            }
            BlockView(display: display)
        }
        .foregroundStyle(.white)
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.accessibilityLabel(at: .now))
    }
}

private struct HeartRateView: View {
    let display: RecordingLiveDisplay
    let size: Font.TextStyle

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill").foregroundStyle(Style.heart).accessibilityHidden(true)
            Text(display.heartRateText).font(.system(size, design: .rounded).monospacedDigit().weight(.bold))
            if display.hasHeartRate { Text("bpm").font(.caption).foregroundStyle(.white.opacity(0.8)) }
        }
    }
}

private struct ElapsedView: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, pauseTime: nil, countsDown: false, showsHours: true)
            .multilineTextAlignment(.trailing)
    }
}

private struct BlockView: View {
    let display: RecordingLiveDisplay

    var body: some View {
        if let block = display.blockText {
            HStack {
                Text(block).font(.subheadline).lineLimit(1)
                Spacer()
                if let end = display.blockEnd(at: .now) {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Style.accent)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

private struct WarningView: View {
    let display: RecordingLiveDisplay

    var body: some View {
        if let warning = display.connectionWarning {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Style.warning)
        }
    }
}
