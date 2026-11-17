import SwiftUI
import UIKit
import RhythmicCore

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "moon.and.sun").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Rhythmic").font(.largeTitle.bold())
            Text("Your plan offers research-informed suggestions for managing jet lag, based on your itinerary and usual sleep habits. It does not measure your body clock, provide medical advice, or guarantee results. Follow it where practical and prioritise adequate rest.")
                .font(.body)
            Spacer()
            Button { model.acceptNotice() } label: { Text("Continue").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(24)
    }
}

/// Preferences. Used during onboarding (plan settings only) and as the full-screen You tab.
/// Plan settings apply on Save, which regenerates the plan and its reminders (existing behaviour);
/// reminders and appearance apply immediately.
struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    var isOnboarding = false
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system

    @State private var p: Preferences = .init(homeZoneID: TimeZone.current.identifier, bedtime: ClockTime(23), wakeTime: ClockTime(7))
    @State private var loaded = false

    var hasChanges: Bool { isOnboarding || model.preferences != p }
    var valid: Bool { p.sleepHours >= 4 && p.sleepHours <= 12 }

    var body: some View {
        Form {
            Section {
                DatePicker("Bedtime", selection: clock(\.bedtime), displayedComponents: .hourAndMinute)
                DatePicker("Wake time", selection: clock(\.wakeTime), displayedComponents: .hourAndMinute)
                Picker("Home time zone", selection: $p.homeZoneID) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }
                .pickerStyle(.navigationLink)
            } header: { Text("Usual sleep") } footer: {
                Text(valid ? "Your plan starts from these times. They're an estimate of your body clock, not a measurement."
                           : "Choose a usual sleep length between 4 and 12 hours.")
            }

            Section {
                Toggle("I rarely sleep on afternoon or daytime flights", isOn: $p.rarelySleepsOnDaytimeFlights)
            } header: { Text("Daytime flights") } footer: {
                Text("When on, the plan never depends on sleeping on a daytime flight.")
            }

            Section {
                Picker("Before the trip", selection: $p.preTravelShift) {
                    Text("Keep my schedule").tag(PreTravelShift.off)
                    Text("Shift gently (30 min/day)").tag(PreTravelShift.gentle)
                    Text("Shift 1 h/day").tag(PreTravelShift.standard)
                }
            } header: { Text("Pre-travel adjustment") }

            Section {
                Picker("Caffeine", selection: $p.caffeine) {
                    Text("I don't use caffeine").tag(CaffeineHabit.none)
                    Text("I use caffeine").tag(CaffeineHabit.regular)
                }
                if p.caffeine != .none {
                    Toggle("Caffeine affects my sleep easily", isOn: $p.caffeineSensitive)
                }
            } header: { Text("Caffeine") } footer: {
                Text("No tracking. The plan just shows when caffeine is fine and when to stop. It never suggests starting.")
            }

            Section {
                Toggle("Show home time in details", isOn: $p.showHomeTime)
            } header: { Text("Times") } footer: {
                Text("Adds your home time when you tap a block or flight.")
            }

            if !isOnboarding {
                if hasChanges {
                    Section {
                        Button("Save changes") { model.save(preferences: p) }.disabled(!valid)
                    } footer: { Text("Saving updates your plan and replaces its reminders.") }
                }

                Section {
                    Toggle("Plan reminders", isOn: Binding(get: { model.remindersActive }, set: { on in Task { await model.setReminders(on) } }))
                        .disabled(model.notificationsDenied)
                    if model.notificationsDenied {
                        Button("Allow notifications in Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                } header: { Text("Notifications") } footer: {
                    Text(model.notificationsDenied
                         ? "Notifications are turned off for Rhythmic in iOS Settings."
                         : model.remindersActive
                         ? "\(model.pendingReminderCount) reminders scheduled on this iPhone. They work offline and stop when the plan ends. They're ordinary notifications, not alarms: Silent mode or Focus can hide them, so set a real alarm if you need to wake."
                         : "Short reminders at key moments: daylight, lights low, coffee cutoff, bedtime and wake time.")
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    NavigationLink("How this plan works") { AboutPlan(plan: model.plan) }
                    NavigationLink("About Rhythmic") { AboutRhythmic() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .tint(Palette.accent)
        .navigationTitle(isOnboarding ? "About you" : "You")
        .toolbar {
            if isOnboarding {
                Button("Next") { model.save(preferences: p) }.disabled(!valid)
            } else if hasChanges {
                Button("Save") { model.save(preferences: p) }.disabled(!valid).fontWeight(.semibold)
            }
        }
        .onAppear {
            if !loaded, let existing = model.preferences { p = existing }
            loaded = true
        }
        .onChange(of: model.preferences) { _, new in if let new { p = new } }
    }

    func clock(_ kp: WritableKeyPath<Preferences, ClockTime>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: p[keyPath: kp].hour, minute: p[keyPath: kp].minute, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                p[keyPath: kp] = ClockTime(c.hour ?? 0, c.minute ?? 0)
            })
    }
}

struct AboutRhythmic: View {
    var body: some View {
        List {
            Section {
                Text("Your plan offers research-informed suggestions for managing jet lag, based on your itinerary and usual sleep habits. It does not measure your body clock, provide medical advice, or guarantee results. Follow it where practical and prioritise adequate rest.")
                Text("Reminders are ordinary notifications, not alarms. Flight times come from your itinerary; Rhythmic doesn't track live delays.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Version") {
                LabeledContent("Rules", value: RuleBook.version)
            }
        }
        .navigationTitle("About Rhythmic")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Trips tab: real trips from your sources, plus import, add and review.
struct TripsView: View {
    @Environment(AppModel.self) private var model
    var openPlan: () -> Void
    @State private var showManual = false
    @State private var showFeed = false
    @State private var showGoogle = false

    var body: some View {
        let result = model.itinerary
        List {
            if model.isBusy {
                Section { HStack(spacing: 10) { ProgressView(); Text("Updating trips…").foregroundStyle(.secondary) } }
            }
            if let err = model.importError {
                Section { Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote) }
            }

            Section {
                if model.upcomingTrips.isEmpty {
                    ContentUnavailableView {
                        Label("No trips yet", systemImage: "airplane")
                    } description: {
                        Text("Add a flight, or connect a calendar source below. Rhythmic only shows flights you add or import.")
                    }
                }
                ForEach(model.upcomingTrips) { trip in
                    let selected = model.state.selectedTripID == trip.id
                    Button {
                        if !selected || model.plan == nil { model.select(trip: trip) }
                        openPlan()
                    } label: { TripCard(trip: trip, status: status(trip, selected: selected), dimmed: !trip.needsShift) }
                        .buttonStyle(.plain)
                        .listRowBackground(Palette.surface)
                        .swipeActions {
                            if hasManual(trip) { Button("Delete", role: .destructive) { model.removeManualFlights(in: trip) } }
                            if selected { Button("Stop plan") { model.clearPlan() }.tint(.orange) }
                        }
                        .contextMenu {
                            if selected { Button("Stop using this plan", systemImage: "xmark.circle") { model.clearPlan() } }
                            if hasManual(trip) { Button("Delete added flights", systemImage: "trash", role: .destructive) { model.removeManualFlights(in: trip) } }
                        }
                }
            } header: { Text("Your trips") }

            if !result.issues.isEmpty {
                Section {
                    ForEach(result.issues, id: \.self) { i in
                        Label(i.message, systemImage: "questionmark.circle").font(.footnote)
                    }
                } header: { Text("Needs your review") } footer: {
                    Text("Rhythmic won't guess missing airports, times or time zones. Add these flights manually if you need them.")
                }
            }

            Section {
                Button { showManual = true } label: { sourceRow("Add a flight manually", icon: "plus", status: "If a flight can't be imported") }
                Button { showGoogle = true } label: {
                    sourceRow("Google Calendar", icon: "calendar",
                              status: !model.google.isConfigured ? "Not set up (needs an OAuth client ID)"
                                : model.google.isSignedIn ? (model.state.googleLastFetched.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Signed in") : "Not connected")
                }
                Button { showFeed = true } label: {
                    sourceRow("TripIt / calendar feed", icon: "link",
                              status: model.feedURLConfigured ? (model.state.feedLastFetched.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Link saved") : "Not connected")
                }
            } header: { Text("Add or import") }

        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .tint(Palette.accent)
        .navigationTitle("Trips")
        .toolbar {
            Button { showManual = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add a flight")
        }
        .refreshable { await model.refreshFeed(); await model.refreshGoogle() }
        .sheet(isPresented: $showManual) { NavigationStack { ManualFlightView() } }
        .sheet(isPresented: $showFeed) { NavigationStack { FeedSetupView() } }
        .sheet(isPresented: $showGoogle) { NavigationStack { GoogleSetupView() } }
    }

    func hasManual(_ trip: Trip) -> Bool { trip.segments.contains { $0.sources.contains { $0.kind == .manual } } }

    func status(_ trip: Trip, selected: Bool) -> String {
        if !trip.needsShift, !selected || model.plan == nil {
            let h = trip.zoneChangeHours
            return h == 0 ? "Same time zone · no shift needed" : "\(h > 0 ? "+" : "−")\(abs(h).formatted()) h · no shift needed"
        }
        guard selected, let plan = model.plan, plan.tripID == trip.id else { return "View plan" }
        let now = Date()
        if now < plan.horizon.start {
            let days = Calendar.current.dateComponents([.day], from: now, to: plan.horizon.start).day ?? 0
            return days <= 0 ? "Plan starts today" : "Plan starts in \(days) day\(days == 1 ? "" : "s")"
        }
        return now < plan.horizon.end ? "Plan active" : "Plan ended"
    }

    func sourceRow(_ title: String, icon: String, status: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24).foregroundStyle(Palette.accent)
            VStack(alignment: .leading) {
                Text(title).foregroundStyle(Palette.ink)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct TripCard: View {
    let trip: Trip
    let status: String
    /// Greyed out: the time change is too small to need a body-clock shift.
    var dimmed = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(TimeFmt.tripDates(trip).uppercased()) · \(trip.title)")
                    .font(.system(size: 10, weight: .semibold)).kerning(0.6).foregroundStyle(Palette.secondary)
                Text(trip.cityTitle).font(.headline.weight(.medium)).foregroundStyle(Palette.ink)
                if let via = trip.viaText { Text(via).font(.caption).foregroundStyle(Palette.secondary) }
                Text(status).font(.caption.weight(.medium)).foregroundStyle(dimmed ? Palette.secondary : Palette.accent).padding(.top, 2)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .opacity(dimmed ? 0.45 : 1)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct ManualFlightView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var carrier = ""
    @State private var number = ""
    @State private var origin = ""
    @State private var destination = ""
    @State private var originZone = ""
    @State private var destinationZone = ""
    @State private var dep = Date()
    @State private var arr = Date().addingTimeInterval(3 * 3600)

    var originAirport: Airport? { Airports.lookup(origin) }
    var destAirport: Airport? { Airports.lookup(destination) }
    var oz: String? { originAirport?.zoneID ?? originZone.nilIfEmpty }
    var dz: String? { destAirport?.zoneID ?? destinationZone.nilIfEmpty }

    var body: some View {
        Form {
            Section("Flight") {
                TextField("Airline code (e.g. ET)", text: $carrier).textInputAutocapitalization(.characters)
                TextField("Flight number", text: $number).keyboardType(.numberPad)
            }
            Section("From") {
                TextField("Airport code (e.g. WDH)", text: $origin).textInputAutocapitalization(.characters)
                zoneRow(airport: originAirport, code: origin, zone: $originZone)
                DatePicker("Departs (local)", selection: $dep).environment(\.timeZone, TimeZone(identifier: oz ?? "UTC")!)
            }
            Section("To") {
                TextField("Airport code (e.g. ADD)", text: $destination).textInputAutocapitalization(.characters)
                zoneRow(airport: destAirport, code: destination, zone: $destinationZone)
                DatePicker("Arrives (local)", selection: $arr).environment(\.timeZone, TimeZone(identifier: dz ?? "UTC")!)
            }
            Section {
                Text("Enter times as shown on your ticket, in each airport's local time.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Add flight")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    guard let oz, let dz else { return }
                    // The pickers show local time in each airport's zone, so we read the wall time back in that zone.
                    let seg = ImportedSegment(
                        source: SourceRef(kind: .manual, externalID: UUID().uuidString, updatedAt: Date()),
                        carrierCode: carrier.nilIfEmpty?.uppercased(), flightNumber: number.nilIfEmpty,
                        origin: origin.uppercased(), destination: destination.uppercased(),
                        departure: .local(LocalDateTime(dep, in: TimeZone(identifier: oz)!), zoneID: oz),
                        arrival: .local(LocalDateTime(arr, in: TimeZone(identifier: dz)!), zoneID: dz),
                        originZoneID: oz, destinationZoneID: dz,
                        rawSummary: "\(carrier.uppercased())\(number) \(origin.uppercased()) to \(destination.uppercased())".trimmingCharacters(in: .whitespaces))
                    model.addManual(seg)
                    dismiss()
                }
                .disabled(origin.count != 3 || destination.count != 3 || oz == nil || dz == nil)
            }
        }
    }

    @ViewBuilder
    func zoneRow(airport: Airport?, code: String, zone: Binding<String>) -> some View {
        if let airport {
            LabeledContent("Time zone", value: airport.zoneID.replacingOccurrences(of: "_", with: " "))
        } else if code.count == 3 {
            Picker("Time zone (unknown airport)", selection: zone) {
                Text("Choose…").tag("")
                ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.navigationLink)
        }
    }
}

struct FeedSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var reveal = false
    @State private var fetching = false

    var parsed: Result<URL, FeedLink.Problem> { FeedLink.normalize(link) }
    var url: URL? { try? parsed.get() }

    var body: some View {
        Form {
            Section {
                HStack {
                    Group {
                        if reveal { TextField("webcal:// or https:// feed link", text: $link, axis: .vertical).lineLimit(1...4) }
                        else { SecureField("webcal:// or https:// feed link", text: $link) }
                    }
                    .textContentType(.URL).keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(reveal ? "Hide link" : "Show link")
                }
                PasteButton(payloadType: String.self) { strings in
                    if let s = strings.first { link = s }
                }
                .labelStyle(.titleAndIcon)
                if !link.isEmpty, case .failure(let p) = parsed {
                    Label(message(p), systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange)
                } else if let url {
                    Label("Link found on \(url.host ?? "")", systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("In TripIt: Settings → Calendar feed. Make sure the feed includes detailed plans, not just trip titles. The link works like a password: it's stored only in this iPhone's Keychain. Feed updates can lag and aren't live airline updates.")
            }
            Section {
                Text("Experimental: this hasn't been tested with a real TripIt feed yet. Check the trips it finds before you rely on them.")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if model.feedURLConfigured {
                Section { Button("Remove feed", role: .destructive) { model.setFeedURL(nil); dismiss() } }
            }
        }
        .navigationTitle("Calendar feed")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if fetching { ProgressView() } else {
                    Button("Save & fetch") {
                        guard let url else { return }
                        model.setFeedURL(url.absoluteString)
                        fetching = true
                        Task { await model.refreshFeed(); fetching = false; dismiss() }
                    }
                    .disabled(url == nil)
                }
            }
        }
    }

    func message(_ p: FeedLink.Problem) -> String {
        switch p {
        case .empty: "Paste your feed link."
        case .noLink: "That doesn't contain a link. In TripIt, copy the calendar feed link (it starts with webcal:// or https://)."
        case .notSecure: "This link isn't secure (http://). Use the https:// or webcal:// version from TripIt."
        }
    }
}

struct GoogleSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var calendars: [GoogleCalendarClient.CalendarInfo] = []
    @State private var chosen: Set<String> = []

    var body: some View {
        Form {
            if !model.google.isConfigured {
                Section {
                    Text("Google Calendar import isn't set up in this build. A developer needs to create an iOS OAuth client in Google Cloud and add its ID to Info.plist (see docs/IMPORT.md). Until then, nothing is connected.")
                        .font(.footnote)
                }
            } else if !model.google.isSignedIn {
                Section {
                    Button("Sign in with Google") { Task { await model.connectGoogle(); await load() } }
                } footer: {
                    Text("Read-only access to your calendar list and events. Rhythmic only reads the calendars you choose, but Google's permission covers all calendars at that level. Calendars that only appear on your phone (device calendars) may not be available here.")
                }
            } else {
                Section("Calendars to scan for flights") {
                    ForEach(calendars) { c in
                        Toggle(c.name + (c.primary ? " (primary)" : ""), isOn: Binding(
                            get: { chosen.contains(c.id) },
                            set: { on in if on { chosen.insert(c.id) } else { chosen.remove(c.id) } }))
                    }
                }
                Section {
                    Button("Disconnect", role: .destructive) { model.disconnectGoogle(); dismiss() }
                }
            }
        }
        .navigationTitle("Google Calendar")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            if model.google.isSignedIn {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        model.setGoogleCalendars(Array(chosen))
                        Task { await model.refreshGoogle(); dismiss() }
                    }.disabled(chosen.isEmpty)
                }
            }
        }
        .task { await load() }
    }

    func load() async {
        guard model.google.isSignedIn else { return }
        calendars = (try? await model.google.calendars()) ?? []
        chosen = Set(model.state.googleCalendarIDs.isEmpty ? calendars.filter(\.primary).map(\.id) : model.state.googleCalendarIDs)
    }
}
