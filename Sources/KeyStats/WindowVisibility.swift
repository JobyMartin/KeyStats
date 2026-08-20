import Foundation

/// Whether each on-demand window (Dashboard, Preferences) is currently
/// open. `AppDelegate` keeps both windows alive after "close"
/// (`isReleasedWhenClosed = false`, for instant reopen — releasing them
/// instead crashes, see the comment in `showDashboard()`), which means
/// their `NSHostingController`'s SwiftUI content stays loaded. SwiftUI
/// keeps ticking a per-window render/update pass (AttributeGraph /
/// DisplayList.ViewUpdater) at display refresh rate for as long as any
/// content is loaded into any window — hidden or not, animating or not.
/// `DashboardView`/`PreferencesView` swap their real body out for a trivial
/// placeholder while their flag here is false, which stops that tick
/// without touching window lifecycle at all.
final class WindowVisibility: ObservableObject {
    static let shared = WindowVisibility()
    @Published var dashboardVisible = false
    @Published var preferencesVisible = false
    private init() {}
}
