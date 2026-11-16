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
    @State private var showItinerary = false
    @State private var showPreferences = false

    var body: some View {
        if !model.state.acceptedNotice {
            OnboardingView()
        } else if model.preferences == nil {
            NavigationStack { PreferencesView(isOnboarding: true) }
        } else {
            NavigationStack {
                Group {
                    if let plan = model.plan {
                        PlanView(plan: plan)
                    } else {
                        ContentUnavailableView {
                            Label("No plan yet", systemImage: "airplane.departure")
                        } description: {
                            Text("Connect a flight source or try the sample trip, then choose a trip.")
                        } actions: {
                            Button("Add flights") { showItinerary = true }.buttonStyle(.borderedProminent)
                        }
                    }
                }
                .navigationTitle("Rhythmic")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { showPreferences = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Preferences") }
                    ToolbarItem(placement: .topBarTrailing) { Button { showItinerary = true } label: { Image(systemName: "airplane") }.accessibilityLabel("Itinerary") }
                }
                .alert("Plan update", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
                    Button("OK") { model.notice = nil }
                } message: { Text(model.notice ?? "") }
                .sheet(isPresented: $showItinerary) {
                    NavigationStack { ItineraryView().toolbar { Button("Done") { showItinerary = false } } }
                }
                .sheet(isPresented: $showPreferences) { NavigationStack { PreferencesView() } }
            }
        }
    }
}
