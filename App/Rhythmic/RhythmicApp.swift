import SwiftUI
import RhythmicCore

@main
struct RhythmicApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() { NotificationScheduler.shared.install() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: scenePhase) { _, phase in
                    // Top up reminders (iOS caps pending notifications) and drop any that are stale.
                    if phase == .active { Task { await model.syncReminders() } }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system
    @State private var tab: Tab = .initial

    enum Tab: String, Hashable {
        case plan, trips, you
        /// Debug builds only: `-RhythmicTab trips` opens a tab directly (for screenshots without taps).
        static var initial: Tab {
            #if DEBUG
            if let s = UserDefaults.standard.string(forKey: "RhythmicTab"), let t = Tab(rawValue: s) { return t }
            #endif
            return .plan
        }
    }

    var body: some View {
        Group {
            if !model.state.acceptedNotice {
                OnboardingView()
            } else if model.preferences == nil {
                NavigationStack { PreferencesView(isOnboarding: true) }
            } else {
                TabView(selection: $tab) {
                    PlanTab(showTrips: { tab = .trips })
                        .tabItem { Label("Plan", systemImage: "clock") }
                        .tag(Tab.plan)
                    NavigationStack { TripsView(openPlan: { tab = .plan }) }
                        .tabItem { Label("Trips", systemImage: "airplane") }
                        .tag(Tab.trips)
                    NavigationStack { PreferencesView() }
                        .tabItem { Label("You", systemImage: "person") }
                        .tag(Tab.you)
                }
                .tint(Palette.ink)
            }
        }
        .alert("Plan update", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
        .onAppear { appearance.apply() }
        .onChange(of: appearance) { _, mode in mode.apply() }
    }
}
