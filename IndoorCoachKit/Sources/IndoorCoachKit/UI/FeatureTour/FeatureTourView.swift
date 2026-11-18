import SwiftUI

/// Where the feature tour is shown. Onboarding ends on "Los geht’s", Help on "Fertig".
public enum FeatureTourContext: Sendable {
    case onboarding
    case help
}

/// Animated introduction to the app's main features (package O2, docs/12).
struct FeatureTourView: View {
    var context: FeatureTourContext
    var onFinish: () -> Void

    @State private var index = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var focusedTitle: Int?

    private var isLast: Bool { TourPage.isLast(index: index) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            pager
            bottomBar
        }
        .background(Theme.canvas)
        .onChange(of: index) { _, new in focusedTitle = new }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: onFinish) {
                Text("Überspringen").frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            }
            .opacity(isLast ? 0 : 1)
            .disabled(isLast)
            .accessibilityHidden(isLast)
            .accessibilityHint("Schließt die Einführung. Du findest sie später im Profil unter Hilfe.")
            .accessibilityIdentifier("tour.skip")
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    @ViewBuilder private var pager: some View {
        #if os(iOS)
        TabView(selection: $index) {
            ForEach(TourPage.allCases) { page in
                pageContent(page).tag(page.rawValue)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        pageContent(TourPage.allCases[index]).id(index).transition(.opacity)
        #endif
    }

    private func pageContent(_ page: TourPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !typeSize.isAccessibilitySize {
                    page.illustration(active: index == page.rawValue)
                }
                Text(page.title)
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusedTitle, equals: page.rawValue)
                Text(page.body)
                    .font(.title3)
                    .foregroundStyle(Theme.rowSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tour.page.\(page.rawValue + 1)")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Button {
                if isLast { onFinish() } else { withAnimation(.snappy(duration: 0.3)) { index += 1 } }
            } label: {
                Text(TourPage.primaryTitle(index: index, context: context)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.jelly)
            .accessibilityIdentifier(isLast ? "tour.finish" : "tour.next")
            TourPageIndicator(current: index, count: TourPage.allCases.count)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.canvas)
    }
}

/// Step dots with the label "Seite x von n".
struct TourPageIndicator: View {
    var current: Int
    var count: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Theme.accent : Theme.rowSecondary)
                    .frame(width: i == current ? 24 : 8, height: 8)
            }
        }
        .frame(minHeight: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TourPage.indicatorLabel(index: current))
        .accessibilityIdentifier("tour.pageIndicator")
    }
}

// MARK: - DEBUG presentation hook

extension View {
    /// DEBUG only: with the launch argument `-uiTour YES` the tour opens full-screen over the app (UI tests, screenshots).
    /// A no-op in release builds. Used by `App/IndoorCoachApp.swift`; onboarding wiring lives in RootView (O1).
    public func featureTourDebugCover() -> some View { modifier(FeatureTourDebugCover()) }
}

private struct FeatureTourDebugCover: ViewModifier {
    @State private var show: Bool = {
        #if DEBUG
        UserDefaults.standard.string(forKey: "uiTour") == "YES"
        #else
        false
        #endif
    }()

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $show) { FeatureTourView(context: .onboarding) { show = false } }
        #else
        content.sheet(isPresented: $show) { FeatureTourView(context: .onboarding) { show = false } }
        #endif
    }
}
