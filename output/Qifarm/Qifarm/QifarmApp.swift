import SwiftUI
import Charts
import HealthKit
import UniformTypeIdentifiers
import CoreLocation

@MainActor
final class StepStore: ObservableObject {
    @Published var periods: [StepPeriod] = []
    @Published var groupedPeriods: [StepPeriod] = []
    @Published var rawPeriods: [StepPeriod] = []
    @Published var queryEnd: Date?
    @Published var loading = false
    @Published var loaded = false
    @Published var message: String?
    @Published var progress = ""
    @Published var updated: Date?
    private let health = HKHealthStore()

    func load() async {
        guard !loading else { return }
        loading = true
        loaded = false
        periods = []
        rawPeriods = []
        groupedPeriods = []
        queryEnd = nil
        message = nil
        updated = nil
        defer { loading = false }
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "Health data is unavailable. Use an iPhone with Health enabled."
            return
        }
        do {
            let type = HKQuantityType(.stepCount)
            try await health.requestAuthorization(toShare: [], read: [type])
            let now = Date()
            progress = "Finding step history…"
            let first: Date? = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: type,
                    predicate: HKQuery.predicateForSamples(withStart: nil, end: now), limit: 1,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) {
                    _, samples, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: samples?.first?.startDate) }
                }
                health.execute(query)
            }
            if let first {
                let calendar = Calendar.current
                let anchor = calendar.startOfDay(for: first)
                var start = anchor
                var groups: [StepPeriod] = []
                // Bound each query's minute allocation while processing the entire history.
                while start < now {
                    try Task.checkCancellation()
                    guard let next = calendar.date(byAdding: .month, value: 1, to: start), next > start else {
                        throw HKError(.errorInvalidArgument)
                    }
                    let end = min(next, now)
                    progress = "Analyzing \(start.formatted(.dateTime.year().month(.wide)))…"
                    groups += try await readPeriods(start: start, end: end, anchor: anchor)
                    start = end
                }
                // Merge query boundaries within each date; midnight remains a hard boundary.
                rawPeriods = StepPeriod.continuous(groups).sorted { $0.start > $1.start }
                groupedPeriods = StepPeriod.grouped(rawPeriods).sorted { $0.start > $1.start }
                periods = groupedPeriods.filter(\.isQualifying)
            }
            queryEnd = now
            loaded = true
            updated = Date()
        } catch {
            rawPeriods = []
            groupedPeriods = []
            queryEnd = nil
            periods = []
            message = "Couldn’t read Health data. Unlock your iPhone and try again. \(error.localizedDescription)"
        }
    }

    private func readPeriods(start: Date, end: Date, anchor: Date) async throws -> [StepPeriod] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .cumulativeSum, anchorDate: anchor,
                intervalComponents: DateComponents(minute: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                guard let collection else {
                    continuation.resume(throwing: HKError(.errorNoData)); return
                }
                var minutes: [StepMinute] = []
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard statistics.startDate >= start, statistics.startDate < end else { return }
                    minutes.append(StepMinute(start: statistics.startDate,
                        end: min(statistics.endDate, end),
                        steps: statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0))
                }
                continuation.resume(returning: StepPeriod.group(minutes))
            }
            health.execute(query)
        }
    }
}

@main
struct QifarmApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ActivityExport: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(periods: [StepPeriod]) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let records: [[String: Any]] = periods.map {
            ["start": formatter.string(from: $0.start), "end": formatter.string(from: $0.end),
             "steps": $0.steps, "breakSeconds": $0.breakSeconds]
        }
        data = (try? JSONSerialization.data(withJSONObject: ["version": 1, "periods": records], options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
    init(trailActivities: [TrailActivity]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = (try? encoder.encode(TrailExport(version: 1, source: "alltrails", activities: trailActivities))) ?? Data()
    }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum ActivitySource: String {
    case health = "iPhone Health"
    case trails = "AllTrails"
}

enum FarmTheme {
    static let actionWidth: CGFloat = 120
    static let accent = Color(red: 0.13, green: 0.38, blue: 0.32)
    static let ink = Color(red: 0.09, green: 0.19, blue: 0.17)
}

struct UniformActionStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .multilineTextAlignment(.center)
            .frame(width: FarmTheme.actionWidth, height: 64)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? FarmTheme.accent : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(prominent ? Color.clear : Color.primary.opacity(0.12)))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = StepStore()
    @StateObject private var trails = TrailStore()
    @StateObject private var cloud = CloudStore()
    @StateObject private var community = CommunityStore()
    @StateObject private var availability = SourceAvailability()
    @State private var section: AppSection = .dashboard
    @AppStorage("qifarm.language") private var language = "en"
    @State private var enabledSources: [ActivitySource] = []
    @State private var selectedSource: ActivitySource = .health
    @State private var showingSourceDetails = false
    @State private var accountForm = false
    @State private var addingSource = false
    @State private var deletingSource = false
    @State private var syncing = false
    @State private var notice: String?

    private var totalMinutes: Double {
        let health = enabledSources.contains(.health) ? store.periods.map {
            QualifiedActivityInterval(start: $0.start, end: $0.end, minutes: $0.walkingMinutes)
        } : []
        let workouts = enabledSources.contains(.trails) ? trails.qualifying.map {
            QualifiedActivityInterval(start: $0.start, end: $0.end, minutes: $0.movingMinutes)
        } : []
        return ActivityTotals.uniqueMinutes(health + workouts)
    }
    private var availableSources: [ActivitySource] {
        HKHealthStore.isHealthDataAvailable() ? (availability.allTrails ? [.health, .trails] : [.health]) : []
    }
    var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .dashboard:
                    DashboardView(cloud: cloud, community: community, minutes: totalMinutes,
                        login: { accountForm = true })
                case .sources: sourceDashboard
                case .buddies: BuddiesView(store: community, cloud: cloud)
                case .leaderboard: LeaderboardView(store: community, cloud: cloud)
                case .sponsors: ContentUnavailableView("Sponsors", systemImage: "building.2", description: Text("No sponsors yet."))
                case .awards: ContentUnavailableView("Awards", systemImage: "medal", description: Text("No awards yet."))
                case .settings: PreferencesView(store: community, cloud: cloud)
                }
            }
            .navigationDestination(isPresented: $showingSourceDetails) {
                SourceDetailsView(source: selectedSource, store: store, trails: trails)
            }
            .navigationTitle(LocalizedStringKey(section.rawValue))
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            TopMenu(selected: $section, signedIn: cloud.user != nil, userName: cloud.user?.displayName,
                canLogOut: !syncing && !cloud.busy,
                onLogOut: { Task { await cloud.logout(); clearData(); community.clear(); section = .dashboard } },
                onSelect: { showingSourceDetails = false })
                .background(Color(.systemGroupedBackground))
        }
        .tint(FarmTheme.accent)
        .environment(\.locale, Locale(identifier: language))
        .task {
            await cloud.restore()
            if cloud.user != nil { await restoreSavedSources() }
        }
        .onChange(of: cloud.user?.id) { previous, current in
            if previous != current { clearData(); community.clear(); section = .dashboard }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && cloud.user != nil && !syncing {
                Task { await restoreSavedSources() }
            }
        }
        .onChange(of: section) { _, _ in
            if cloud.user != nil { Task { await community.reload(cloud) } }
        }
        .sheet(isPresented: $accountForm) {
            AccountForm(cloud: cloud) { Task { await restoreSavedSources() } }
        }
        .confirmationDialog("Add a data source", isPresented: $addingSource) {
            if !availability.allTrails && !enabledSources.contains(.trails) && HKHealthStore.isHealthDataAvailable() {
                Button("Check AllTrails availability") { Task { await availability.checkAllTrails(); notice = availability.message } }
            }
            ForEach(availableSources.filter { !enabledSources.contains($0) }, id: \.self) { source in
                Button(source.rawValue) { Task { await addSource(source) } }
            }
        }
        .confirmationDialog("Delete a saved data source", isPresented: $deletingSource, titleVisibility: .visible) {
            ForEach(enabledSources, id: \.self) { source in
                Button("Delete \(source.rawValue)", role: .destructive) {
                    Task { await deleteSource(source) }
                }
            }
        } message: {
            Text("Removes the source and its saved activity from your account. Original data in Health and AllTrails is unchanged.")
        }
        .onOpenURL { url in
            guard let callbackMessage = AuthCallback.message(for: url) else { return }
            cloud.message = callbackMessage
            accountForm = false
            if cloud.user == nil { section = .dashboard }
        }
    }

    private var sourceDashboard: some View {
            VStack(spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if cloud.user != nil {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("SOURCE MANAGEMENT").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                                    Text("Manage sources").font(.title2.weight(.semibold))
                                }
                                Spacer(minLength: 8)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .center, spacing: 8) {
                                    Label("QUALIFYING ACTIVITY", systemImage: "figure.walk")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    if !enabledSources.isEmpty {
                                        Menu {
                                            ForEach(enabledSources, id: \.self) { source in
                                                Button(source.rawValue) {
                                                    selectedSource = source
                                                    showingSourceDetails = true
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 8) {
                                                Text("Data sources")
                                                Image(systemName: "chevron.down").font(.caption)
                                            }.frame(width: FarmTheme.actionWidth, height: 64)
                                        }
                                        .foregroundStyle(.white)
                                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.22)))
                                        .disabled(syncing)
                                        .accessibilityHint("Opens the selected source in its own activity view")
                                    }
                                }
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(totalMinutes.formatted(.number.precision(.fractionLength(1))))
                                        .font(.system(size: 42, weight: .semibold, design: .rounded)).monospacedDigit()
                                        .minimumScaleFactor(0.6).lineLimit(1)
                                    Text("min").font(.title3).foregroundStyle(.white.opacity(0.75))
                                }
                                Text("All connected sources · overlaps counted once").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                            }
                            .foregroundStyle(.white).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(LinearGradient(colors: [FarmTheme.ink, FarmTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .accessibilityElement(children: .combine)
                            Text("Overlapping activity from multiple sources is counted once in the dashboard total.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button {
                                    if HKHealthStore.isHealthDataAvailable() { addingSource = true }
                                    else { notice = "HealthKit sources are unavailable on this device. Existing cloud data can still be viewed." }
                                } label: { Label("Add source", systemImage: "plus.circle") }
                                    .buttonStyle(UniformActionStyle(prominent: false))
                                    .disabled(enabledSources.contains(.health) && enabledSources.contains(.trails))
                                Button { Task { await refreshSources() } } label: { Label("Refresh all", systemImage: "arrow.clockwise") }
                            }.disabled(syncing)
                            Button { deletingSource = true } label: {
                                Label("Delete source", systemImage: "trash")
                            }
                            .buttonStyle(UniformActionStyle(prominent: false))
                            .disabled(syncing || cloud.busy || enabledSources.isEmpty)
                            if enabledSources.isEmpty { Text("Add iPhone Health or AllTrails to begin.").font(.subheadline).foregroundStyle(.secondary) }
                        } else {
                            Spacer(minLength: 32)
                            Image(systemName: "leaf.circle.fill").font(.system(size: 64)).foregroundStyle(FarmTheme.accent)
                            Text("元气农场").font(.system(size: 34, weight: .semibold))
                            Text("A clearer view of your activity.").font(.title3).foregroundStyle(.secondary)
                            Text("Connect your walking history, track qualifying minutes, and keep your progress together.")
                                .font(.body).foregroundStyle(.secondary).lineSpacing(4)
                            Spacer(minLength: 16)
                            Button("Register / Log in") { accountForm = true }
                            Text("Sign in to save activity data privately in Supabase and restore it on your other devices.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if syncing { ProgressView("Refreshing and syncing sources…") }
                        if let notice { Label(notice, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12)) }
                        if let message = cloud.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    }.buttonStyle(UniformActionStyle()).padding(.horizontal, 12).padding(.vertical, 16)
                }
                .frame(maxHeight: .infinity)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.07)))
                .padding(.horizontal, 8)

            }
    }

    private func clearData(resetNavigation: Bool = true) {
        if resetNavigation { showingSourceDetails = false }
        enabledSources = []
        store.periods = []; store.rawPeriods = []; store.groupedPeriods = []; store.loaded = false
        store.queryEnd = nil; store.updated = nil; store.message = nil
        trails.activities = []; trails.loaded = false; trails.message = nil; trails.lastRefreshSucceeded = false
        notice = nil
    }
    private func restoreSavedSources() async {
        guard !syncing else { return }
        syncing = true
        do {
            let rows = try await cloud.sources()
            // Validate the complete cloud response before replacing any visible account data.
            var restoredSources: [ActivitySource] = []
            var restoredPeriods: [StepPeriod] = []
            var restoredActivities: [TrailActivity] = []
            for row in rows {
                let source: ActivitySource
                switch row.id {
                case "health": source = .health
                case "trails": source = .trails
                default: throw SnapshotError.unsupportedSource
                }
                guard !restoredSources.contains(source) else { throw SnapshotError.duplicateSource }
                restoredSources.append(source)
                if row.rawData != Data("{}".utf8) {
                    if source == .trails { restoredActivities = try TrailExport.read(row.rawData) }
                    else { restoredPeriods = try CloudStore.readStepPeriods(row.rawData) }
                }
            }
            let wasShowingDetails = showingSourceDetails
            let previousSelection = selectedSource
            clearData(resetNavigation: false)
            enabledSources = restoredSources
            store.rawPeriods = restoredPeriods
            store.groupedPeriods = StepPeriod.grouped(restoredPeriods).sorted { $0.start > $1.start }
            store.periods = store.groupedPeriods.filter(\.isQualifying)
            store.loaded = restoredSources.contains(.health)
            trails.activities = restoredActivities
            trails.loaded = restoredSources.contains(.trails)
            if enabledSources.contains(previousSelection) {
                selectedSource = previousSelection
                showingSourceDetails = wasShowingDetails
            } else if let first = enabledSources.first { selectedSource = first }
            syncing = false
            await community.reload(cloud)
            if let profile = community.profile, profile.time_zone != TimeZone.current.identifier {
                try await cloud.preferences(location: profile.location, language: profile.language)
                await community.reload(cloud)
            }
            if let savedLanguage = community.profile?.language { language = savedLanguage }
            notice = "Saved source data restored. Use Refresh all for new HealthKit readings."
        } catch {
            notice = "Could not restore cloud data: \(error.localizedDescription). Previous device results were kept. Check Supabase connectivity and that both schema.sql and activity-storage.sql are installed."
            syncing = false
        }
    }
    private func addSource(_ source: ActivitySource) async {
        guard !syncing, !enabledSources.contains(source) else { return }
        syncing = true
        do {
            try await cloud.save(id: source == .health ? "health" : "trails", rawData: Data("{}".utf8), minutes: 0, create: true)
            selectedSource = source
            syncing = false
            await restoreSavedSources()
        } catch { notice = "Source was not added: \(error.localizedDescription)"; syncing = false }
    }
    private func deleteSource(_ source: ActivitySource) async {
        guard !syncing, cloud.user != nil, enabledSources.contains(source) else { return }
        syncing = true
        defer { syncing = false }
        do {
            try await cloud.deleteSource(id: source == .health ? "health" : "trails")
            enabledSources.removeAll { $0 == source }
            if source == .health {
                store.rawPeriods = []; store.groupedPeriods = []; store.periods = []
                store.loaded = false; store.queryEnd = nil; store.updated = nil; store.message = nil
            } else {
                trails.activities = []; trails.loaded = false
                trails.message = nil; trails.lastRefreshSucceeded = false
            }
            if selectedSource == source {
                showingSourceDetails = false
                selectedSource = enabledSources.first ?? .health
            }
            notice = "\(source.rawValue) and its saved activity were deleted. Qualifying totals have been updated."
        } catch {
            notice = "Could not delete \(source.rawValue): \(error.localizedDescription). The source and its data are still available."
        }
    }

    private func refreshSources() async {
        guard !syncing, cloud.user != nil else { return }
        syncing = true
        defer { syncing = false }
        var errors: [String] = []
        for source in enabledSources {
            do {
                if source == .health {
                    let previous = store.rawPeriods
                    let wasLoaded = store.loaded
                    await store.load()
                    guard store.loaded else {
                        store.rawPeriods = previous
                        store.groupedPeriods = StepPeriod.grouped(previous).sorted { $0.start > $1.start }
                        store.periods = store.groupedPeriods.filter(\.isQualifying)
                        store.loaded = wasLoaded
                        errors.append(store.message ?? "Health refresh failed")
                        continue
                    }
                    if store.rawPeriods.isEmpty && !previous.isEmpty {
                        store.rawPeriods = previous
                        store.groupedPeriods = StepPeriod.grouped(previous).sorted { $0.start > $1.start }
                        store.periods = store.groupedPeriods.filter(\.isQualifying)
                        errors.append("Health returned no readable data; previous saved activity was kept. Check read permission.")
                        continue
                    }
                    try await cloud.save(id: "health", rawData: ActivityExport(periods: store.rawPeriods).data,
                        minutes: store.periods.reduce(0) { $0 + $1.walkingMinutes })
                } else {
                    let previous = trails.activities
                    await trails.loadHealthWorkouts()
                    guard trails.lastRefreshSucceeded else { errors.append(trails.message ?? "AllTrails refresh failed"); continue }
                    if trails.activities.isEmpty && !previous.isEmpty {
                        trails.activities = previous
                        errors.append("AllTrails returned no readable workouts; previous saved activity was kept. Check read permission.")
                        continue
                    }
                    try await cloud.save(id: "trails", rawData: ActivityExport(trailActivities: trails.activities).data,
                        minutes: trails.qualifying.reduce(0) { $0 + $1.movingMinutes })
                }
            } catch { errors.append("\(source.rawValue) cloud save failed: \(error.localizedDescription). Results remain on this device.") }
        }
        await community.reload(cloud)
        notice = errors.isEmpty ? (enabledSources.isEmpty ? "Add a source to start tracking activity." : "All enabled sources refreshed and saved.") : errors.joined(separator: "\n")
    }
}


struct SourceDetailsView: View {
    let source: ActivitySource
    @ObservedObject var store: StepStore
    @ObservedObject var trails: TrailStore
    @Environment(\.dismiss) private var dismiss
    @State private var onlyQualifying = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ACTIVITY DETAILS").font(.caption2.weight(.semibold)).tracking(1)
                        .foregroundStyle(.secondary)
                    Text(source.rawValue).font(.title2.weight(.semibold))
                }
                Spacer(minLength: 8)
                Button { dismiss() } label: { Label("Go back", systemImage: "arrow.left") }
                    .buttonStyle(UniformActionStyle(prominent: false))
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))

            VStack(spacing: 12) {
                Label("Data", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: FarmTheme.actionWidth, height: 64)
                    .foregroundStyle(.white)
                    .background(FarmTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityAddTraits(.isSelected)
                    .padding(.top, 16)
                Toggle("Only show qualifying activity", isOn: $onlyQualifying).padding(.horizontal, 16)
                Divider().padding(.horizontal, 16)
                if source == .health { HealthDataView(store: store, onlyQualifying: onlyQualifying) }
                else { TrailDataView(store: trails, onlyQualifying: onlyQualifying) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.1)))
        }
        .padding(8)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(source.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
}


struct HealthDataView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var store: StepStore
    var onlyQualifying = false
    private var byDate: [Date: [StepPeriod]] {
        Dictionary(grouping: onlyQualifying ? store.periods : store.groupedPeriods) { Calendar.current.startOfDay(for: $0.start) }
    }
    private var dailyMinutes: [Date: Double] {
        Dictionary(grouping: store.periods) { Calendar.current.startOfDay(for: $0.start) }
            .mapValues { $0.reduce(0) { $0 + $1.walkingMinutes } }
    }
    var body: some View {
        let groups = byDate
        let totals = dailyMinutes
        List {
            Section {
                Text("Qualifying active time").font(.subheadline).foregroundStyle(.secondary)
                Text("\(store.periods.reduce(0) { $0 + $1.walkingMinutes }.formatted(.number.precision(.fractionLength(1)))) min")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                Text("\(store.periods.count) passed · \(store.groupedPeriods.count - store.periods.count) failed")
                    .font(.subheadline)
                Text(onlyQualifying ? "Only qualifying periods are shown. Totals and the chart include qualifying active time only." : "All merged periods are shown below. Only passed periods contribute to totals and the chart. Health minute buckets are estimates; breaks are excluded from active time but included in cadence.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Qualifying walking minutes by date") {
                if totals.isEmpty { Text("No qualifying activity to chart.").foregroundStyle(.secondary) }
                else {
                    Chart(totals.keys.sorted(), id: \.self) { date in
                        BarMark(x: .value("Date", date, unit: .day), y: .value("Active minutes", totals[date] ?? 0))
                            .foregroundStyle(FarmTheme.accent)
                            .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                            .accessibilityValue("\((totals[date] ?? 0).formatted(.number.precision(.fractionLength(1)))) qualifying minutes")
                    }
                    .chartYAxisLabel("Minutes")
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: 14 * 24 * 60 * 60)
                    .chartScrollPosition(initialX: Calendar.current.date(byAdding: .day, value: -13,
                        to: totals.keys.max() ?? Date()) ?? Date())
                    .frame(height: 220)
                }
            }
            if groups.isEmpty {
                ContentUnavailableView("No readable step activity", systemImage: "figure.walk",
                    description: Text("Return to the dashboard and refresh. Check Steps read access in Health if needed."))
            }
            ForEach(groups.keys.sorted(by: >), id: \.self) { date in
                Section(date.formatted(.dateTime.weekday(.wide).year().month(.wide).day().locale(locale))) {
                    Text("Qualifying date total: \((totals[date] ?? 0).formatted(.number.precision(.fractionLength(1)))) active minutes")
                        .font(.headline)
                    ForEach(groups[date] ?? []) { period in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(period.isQualifying ? "Passed" : "Failed",
                                  systemImage: period.isQualifying ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.headline).foregroundStyle(period.isQualifying ? FarmTheme.accent : .red)
                            Text(LocalizedStringKey(period.filterExplanation)).font(.caption)
                            Text("Start: \(period.start.formatted(.dateTime.month(.abbreviated).day().hour().minute().timeZone(.iso8601(.short)).locale(locale)))")
                            Text("End: \(period.end.formatted(.dateTime.month(.abbreviated).day().hour().minute().timeZone(.iso8601(.short)).locale(locale)))")
                            Text("Total duration: \(period.elapsedMinutes.formatted(.number.precision(.fractionLength(1)))) min")
                            Text("Active time: \(period.walkingMinutes.formatted(.number.precision(.fractionLength(1)))) min · Breaks: \((period.breakSeconds / 60).formatted(.number.precision(.fractionLength(1)))) min")
                            Text("\(period.steps.formatted(.number.precision(.fractionLength(0)))) steps · \(period.averageStepsPerMinute.formatted(.number.precision(.fractionLength(2)))) steps / elapsed min")
                        }.font(.subheadline).padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

@MainActor
final class TrailStore: ObservableObject {
    @Published var activities: [TrailActivity] = []
    private let health = HKHealthStore()
    @Published var loaded = false
    @Published var loading = false
    @Published var message: String?
    @Published var lastRefreshSucceeded = false
    var qualifying: [TrailActivity] { activities.filter(\.isQualifying) }

    func loadHealthWorkouts() async {
        guard !loading else { return }
        lastRefreshSucceeded = false
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "Health is unavailable. Run this app on your iPhone."
            return
        }
        loading = true
        defer { loading = false }
        do {
            let type = HKObjectType.workoutType()
            try await health.requestAuthorization(toShare: [], read: [type])
            let cutoff = Date()
            let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: type,
                    predicate: HKQuery.predicateForSamples(withStart: nil, end: cutoff),
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: samples as? [HKWorkout] ?? []) }
                }
                health.execute(query)
            }
            let matching = workouts.filter {
                HealthTrailWorkout.isAllTrails(sourceName: $0.sourceRevision.source.name,
                    bundleIdentifier: $0.sourceRevision.source.bundleIdentifier) && $0.endDate <= cutoff
            }
            activities = TrailActivity.deduplicated(matching.map { workout in
                let source = workout.sourceRevision.source
                let gain = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
                let distance = workout.totalDistance?.doubleValue(for: .meter())
                return TrailActivity(id: workout.uuid.uuidString, name: "AllTrails workout", start: workout.startDate, end: workout.endDate,
                    movingMinutes: workout.duration.isFinite ? workout.duration / 60 : 0,
                    distanceMeters: distance.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
                    elevationGainMeters: gain.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
                    sourceName: source.name, sourceBundleIdentifier: source.bundleIdentifier)
            })
            loaded = true
            lastRefreshSucceeded = true
            message = matching.isEmpty
                ? "No readable AllTrails workouts in Health. Record and save a new activity after enabling sync, then refresh. Check Workouts read access for 元气农场. Health does not disclose whether read access was denied."
                : "Read \(matching.count) AllTrails workouts through \(cutoff.formatted(date: .abbreviated, time: .shortened)). Average speed uses recorded distance and Health workout duration. Open Data to inspect pass/fail results and reasons."
        } catch {
            message = "Couldn’t read AllTrails workouts: \(error.localizedDescription) Previous results remain unchanged."
        }
    }

}

struct TrailDataView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var store: TrailStore
    var onlyQualifying = false
    private var rows: [TrailActivity] { onlyQualifying ? store.qualifying : store.activities }
    private var byDate: [Date: [TrailActivity]] {
        Dictionary(grouping: rows) { Calendar.current.startOfDay(for: $0.start) }
    }
    var body: some View {
        let groups = byDate
        List {
            Section {
                Text("AllTrails").font(.headline)
                Text(onlyQualifying ? "Only qualifying activities are shown. Average speed must be 2–5 km/h, inclusive." : "All activities show pass/fail results. Only average speeds from 2 to 5 km/h, inclusive, contribute to totals.")
                Text("Moving time uses Health workout duration, not elapsed start-to-end time. It may differ from AllTrails’ own moving time.").font(.caption)
                Text("Qualifying total: \(store.qualifying.reduce(0) { $0 + $1.movingMinutes }.formatted(.number.precision(.fractionLength(1)))) moving minutes")
                    .font(.headline)
                if let message = store.message { Text(message).font(.caption) }
            }
            if rows.isEmpty {
                ContentUnavailableView("No activities in this view", systemImage: "mountain.2",
                    description: Text("Return to the dashboard and refresh AllTrails. Check Workouts read access in Health if needed."))
            }
            if !store.qualifying.isEmpty {
                Section("Moving minutes by date") {
                    Chart(groups.keys.filter { date in (groups[date] ?? []).contains(where: \.isQualifying) }.sorted(), id: \.self) { date in
                        BarMark(x: .value("Date", date, unit: .day),
                                y: .value("Moving minutes", (groups[date] ?? []).filter(\.isQualifying).reduce(0) { $0 + $1.movingMinutes }))
                            .foregroundStyle(.teal)
                    }
                    .chartYAxisLabel("Minutes").frame(height: 220)
                }
            }
            ForEach(groups.keys.sorted(by: >), id: \.self) { date in
                Section(date.formatted(.dateTime.weekday(.wide).year().month(.wide).day().locale(locale))) {
                    Text("Qualifying date total: \((groups[date] ?? []).filter(\.isQualifying).reduce(0) { $0 + $1.movingMinutes }.formatted(.number.precision(.fractionLength(1)))) moving minutes")
                        .font(.headline)
                    ForEach(groups[date] ?? []) { activity in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(activity.name).font(.headline)
                            Text("\(activity.movingMinutes.formatted(.number.precision(.fractionLength(1)))) moving minutes (Health duration)")
                            if let distance = activity.distanceMeters {
                                Text("Distance: \((distance / 1000).formatted(.number.precision(.fractionLength(2)))) km")
                            } else { Text("Distance: unavailable") }
                            if let gain = activity.elevationGainMeters {
                                Text("Elevation gain: \(gain.formatted(.number.precision(.fractionLength(1)))) m")
                            } else { Text("Elevation gain: unavailable") }
                            if let speed = activity.averageSpeedKmh {
                                Text("Average speed: \(speed.formatted(.number.precision(.fractionLength(3)))) km/h")
                            } else { Text("Average speed: unavailable") }
                            Text("Start: \(activity.start.formatted(.dateTime.year().month().day().hour().minute().second().locale(locale)))")
                            Text("End: \(activity.end.formatted(.dateTime.year().month().day().hour().minute().second().locale(locale)))")
                            Label(LocalizedStringKey(activity.filterExplanation), systemImage: activity.isQualifying ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(activity.isQualifying ? FarmTheme.accent : .red)
                            if let sourceName = activity.sourceName {
                                Text("Source: \(sourceName) · \(activity.sourceBundleIdentifier ?? "")").font(.caption)
                            }
                        }.font(.subheadline).padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("AllTrails · Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
