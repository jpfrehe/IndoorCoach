import SwiftUI

/// "Powered by Strava" attribution next to Strava-derived data (Strava brand guidelines).
/// Text instead of the official logo asset, which is not bundled. Only for real Strava data, never in demo mode.
struct PoweredByStrava: View {
    var body: some View {
        Text("Powered by Strava")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.strava)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
