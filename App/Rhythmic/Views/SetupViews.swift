import SwiftUI
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

struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var isOnboarding = false

    @State private var p: Preferences = .init(homeZoneID: TimeZone.current.identifier, bedtime: ClockTime(23), wakeTime: ClockTime(7))

    var body: some View {
        Form {
            Section {
                Picker("Home time zone", selection: $p.homeZoneID) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }
                .pickerStyle(.navigationLink)
                DatePicker("Usual bedtime", selection: clock(\.bedtime), displayedComponents: .hourAndMinute)
                DatePicker("Usual wake time", selection: clock(\.wakeTime), displayedComponents: .hourAndMinute)
            } header: { Text("Your usual schedule") } footer: {
                Text("Your plan starts from these times. They're an estimate of your body clock, not a measurement.")
            }

            Section {
                Toggle("I rarely sleep on afternoon or daytime flights", isOn: $p.rarelySleepsOnDaytimeFlights)
                Picker("Before the trip", selection: $p.preTravelShift) {
                    Text("Keep my schedule").tag(PreTravelShift.off)
                    Text("Shift gently (30 min/day)").tag(PreTravelShift.gentle)
                    Text("Shift 1 h/day").tag(PreTravelShift.standard)
                }
            } header: { Text("Sleep") } footer: {
                Text("If you rarely sleep on daytime flights, the plan never depends on it.")
            }

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
                Toggle("Show home time alongside local time", isOn: $p.showHomeTime)
            }

            Section {
                Button("Use demo profile (22:00–05:00, Windhoek)") { p = .demo }
            }
        }
        .navigationTitle(isOnboarding ? "About you" : "Preferences")
        .toolbar {
            Button(isOnboarding ? "Next" : "Save") { model.save(preferences: p); if !isOnboarding { dismiss() } }
                .disabled(p.sleepHours < 4 || p.sleepHours > 12)
        }
        .onAppear { if let existing = model.preferences { p = existing } }
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

/// Itinerary sources + review. Asks only about missing or conflicting essentials.
struct ItineraryView: View {
    @Environment(AppModel.self) private var model
    @State private var showManual = false
    @State private var showFeed = false
    @State private var showGoogle = false

    var body: some View {
        let result = model.itinerary
        List {
            Section {
                Button { showGoogle = true } label: {
                    sourceRow("Google Calendar", icon: "calendar",
                              status: !model.google.isConfigured ? "Not set up (needs an OAuth client ID)"
                                : model.google.isSignedIn ? (model.state.googleLastFetched.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Signed in") : "Not connected")
                }
                Button { showFeed = true } label: {
                    sourceRow("TripIt / calendar feed", icon: "link",
                              status: model.feedURLConfigured ? (model.state.feedLastFetched.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Link saved") : "Not connected")
                }
                Toggle(isOn: Binding(get: { model.state.sampleEnabled }, set: { model.setSample($0) })) {
                    sourceRow("Sample trip (Windhoek → Singapore)", icon: "testtube.2", status: "Demo data, not real flights")
                }
                Button { showManual = true } label: { sourceRow("Add a flight manually", icon: "plus", status: "If a flight can't be imported") }
            } header: { Text("Sources") }

            if let err = model.importError {
                Section { Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote) }
            }

            if !result.issues.isEmpty || !result.incomplete.isEmpty {
                Section {
                    ForEach(result.issues, id: \.self) { i in
                        Label(i.message, systemImage: "questionmark.circle").font(.footnote)
                    }
                } header: { Text("Needs your review") } footer: {
                    Text("Rhythmic won't guess missing airports, times or time zones. Add these flights manually if you need them.")
                }
            }

            Section("Trips") {
                if model.upcomingTrips.isEmpty { Text("No upcoming flights found yet.").foregroundStyle(.secondary) }
                ForEach(model.upcomingTrips) { trip in
                    Button { model.select(trip: trip) } label: { TripRow(trip: trip, selected: model.state.selectedTripID == trip.id) }
                        .buttonStyle(.plain)
                }
            }

            if !model.state.manualSegments.isEmpty {
                Section("Manual flights") {
                    ForEach(model.state.manualSegments, id: \.source.externalID) { s in
                        Text(s.rawSummary ?? "Flight").font(.footnote)
                    }
                    .onDelete { idx in idx.map { model.state.manualSegments[$0].source.externalID }.forEach(model.removeManual) }
                }
            }
        }
        .navigationTitle("Itinerary")
        .refreshable { await model.refreshFeed(); await model.refreshGoogle() }
        .sheet(isPresented: $showManual) { NavigationStack { ManualFlightView() } }
        .sheet(isPresented: $showFeed) { NavigationStack { FeedSetupView() } }
        .sheet(isPresented: $showGoogle) { NavigationStack { GoogleSetupView() } }
    }

    func sourceRow(_ title: String, icon: String, status: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24)
            VStack(alignment: .leading) {
                Text(title)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct TripRow: View {
    let trip: Trip
    let selected: Bool
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.title).font(.headline)
                ForEach(trip.segments) { s in
                    Text("\(s.displayFlight): \(TimeFmt.dayTime(s.departure, s.originZoneID)) \(TimeFmt.zoneAbbrev(s.originZoneID, at: s.departure)) → \(TimeFmt.dayTime(s.arrival, s.destinationZoneID)) \(TimeFmt.zoneAbbrev(s.destinationZoneID, at: s.arrival))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if trip.segments.flatMap(\.sources).contains(where: { $0.kind == .sample }) {
                    Text("Sample data").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
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
                        rawSummary: "\(carrier.uppercased()) \(number) \(origin.uppercased()) to \(destination.uppercased())")
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

    var body: some View {
        Form {
            Section {
                SecureField("webcal:// or https:// feed link", text: $link)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
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
                Button("Save & fetch") {
                    model.setFeedURL(link)
                    Task { await model.refreshFeed(); dismiss() }
                }
                .disabled(URL(string: link) == nil || link.isEmpty)
            }
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
