import SwiftUI
import Charts
import HealthKit
import UniformTypeIdentifiers

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
        let records: [[String: Any]] = periods.map {
            ["start": formatter.string(from: $0.start), "end": formatter.string(from: $0.end),
             "steps": $0.steps, "breakSeconds": $0.breakSeconds]
        }
        data = (try? JSONSerialization.data(withJSONObject: ["version": 1, "periods": records], options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ContentView: View {
    @StateObject private var store = StepStore()
    @State private var exporting = false
    @State private var exportError: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "figure.walk.circle.fill")
                        .font(.system(size: 52)).foregroundStyle(.teal).accessibilityHidden(true)
                    Text("Your longer walks.").font(.largeTitle.bold())
                    Text("Walking periods over 30 active minutes averaging more than 60 steps per walking minute. Breaks under 5 minutes are merged.")
                        .foregroundStyle(.secondary)
                    HStack(alignment: .center, spacing: 12) {
                        Button { Task { await store.load() } } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "heart.fill")
                                Text("iPhone Health App")
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 60)
                        }
                        .buttonStyle(.borderedProminent).tint(.teal)
                        .disabled(store.loading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TOTAL TIME").font(.caption.bold()).foregroundStyle(.secondary)
                            if store.loading {
                                ProgressView("Calculating…").font(.caption)
                            } else if store.loaded {
                                Text(store.periods.reduce(0) { $0 + $1.walkingMinutes },
                                     format: .number.precision(.fractionLength(1)))
                                    .font(.system(.title2, design: .rounded).bold())
                                    .monospacedDigit()
                                Text("walking minutes").font(.caption)
                            } else {
                                Text("—").font(.title2.bold())
                                Text("walking minutes").font(.caption)
                            }
                            Text("All dates · excludes breaks")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .padding(12)
                        .background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("overallWalkingTime")
                    }
                    Text("Allow Steps read access to analyze all available step history. Your data stays on this device. Long histories may take a while to process.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if store.loading { ProgressView(store.progress) }
                    if let message = store.message {
                        Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    }
                    NavigationLink {
                        UnfilteredPeriodsView(store: store)
                    } label: {
                        Label("Unfiltered", systemImage: "rectangle.3.group")
                    }
                    .disabled(!store.loaded || store.loading)
                    NavigationLink {
                        FilteredPeriodsView(store: store)
                    } label: {
                        Label("Filtered", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .disabled(!store.loaded || store.loading)
                    if store.loaded && !store.loading {
                        Button("Export activity for web app", systemImage: "square.and.arrow.up") { exporting = true }
                        Text("Save the JSON file, then import it in the 元气农场 web app. It contains activity times and step counts.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let exportError { Text(exportError).foregroundStyle(.red) }
                    if let updated = store.updated {
                        Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Continuous activity requires gaps under one minute, estimated from Health’s one-minute buckets. A zero or missing minute ends an initial period. Breaks strictly under 5 minutes are then merged. Selection uses active time excluding breaks. Displayed walking time and totals exclude breaks. Average pace is total steps divided by walking minutes, excluding breaks. Exactly 30 active minutes or 60 steps per walking minute do not qualify. Periods split at local midnight before merging and filtering; each date qualifies independently. Totals include qualifying periods only. Health may distribute samples across minutes, so brief pauses cannot be identified precisely. Today’s latest period may still be in progress. Times use your local time zone; offsets distinguish repeated hours.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .navigationTitle("元气农场")
            .background(Color(.systemGroupedBackground))
        }.tint(.teal)
        .fileExporter(isPresented: $exporting, document: ActivityExport(periods: store.rawPeriods),
                      contentType: .json, defaultFilename: "qifarm-activity") { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
            else { exportError = nil }
        }
    }
}


struct UnfilteredPeriodsView: View {
    @ObservedObject var store: StepStore
    private var byDate: [Date: [StepPeriod]] {
        Dictionary(grouping: store.groupedPeriods) { Calendar.current.startOfDay(for: $0.start) }
    }

    var body: some View {
        let grouped = byDate
        List {
            Section {
                Text("All activity after merging breaks under five minutes, before duration/cadence filtering. Short and slower groups are included. Midnight splits groups.")
                Text("These are one-minute HealthKit estimates, not individual footstep records. Zero-step intervals are omitted.")
                    .foregroundStyle(.secondary)
                if let end = store.queryEnd {
                    Text("Data queried through \(end.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption)
                }
                Text("\(store.groupedPeriods.count) periods · \(store.groupedPeriods.reduce(0) { $0 + $1.walkingMinutes }.formatted(.number.precision(.fractionLength(1)))) active minutes")
                    .font(.headline)
            }
            if store.groupedPeriods.isEmpty {
                ContentUnavailableView("No readable activity", systemImage: "figure.walk",
                    description: Text("Check Steps access in Health, then return to the main page and refresh."))
            }
            ForEach(grouped.keys.sorted(by: >), id: \.self) { date in
                Section {
                    let periods = grouped[date] ?? []
                    Text("Date total: \(periods.reduce(0) { $0 + $1.walkingMinutes }.formatted(.number.precision(.fractionLength(1)))) active minutes")
                        .font(.subheadline.bold())
                    ForEach(periods) { period in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(period.walkingMinutes.formatted(.number.precision(.fractionLength(1)))) active minutes · \(period.steps.formatted(.number.precision(.fractionLength(0)))) steps")
                                .font(.headline)
                            Text("Average: \(period.averageStepsPerMinute.formatted(.number.precision(.fractionLength(1)))) steps per active minute")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Break time: \((period.breakSeconds / 60).formatted(.number.precision(.fractionLength(1)))) minutes")
                            Text("Start: \(period.start.formatted(.dateTime.hour().minute().timeZone(.iso8601(.short))))")
                            Text("End: \(period.end.formatted(.dateTime.hour().minute().timeZone(.iso8601(.short))))")

                        }.padding(.vertical, 4)
                    }
                } header: {
                    Text(date, format: .dateTime.year().month(.wide).day())
                }
            }
        }
        .navigationTitle("Unfiltered")
        .navigationBarTitleDisplayMode(.inline)
    }
}


struct FilteredPeriodsView: View {
    @ObservedObject var store: StepStore
    private var dailyMinutes: [Date: Double] {
        Dictionary(grouping: store.periods) { Calendar.current.startOfDay(for: $0.start) }
            .mapValues { $0.reduce(0) { $0 + $1.walkingMinutes } }
    }
    private var dates: [Date] { dailyMinutes.keys.sorted(by: >) }

    private var walkingChart: some View {
        let totals = dailyMinutes
        let orderedDates = totals.keys.sorted()
        return VStack(alignment: .leading, spacing: 12) {
            Text("Walking minutes by date").font(.title2.bold())
            Text("Qualifying active time, excluding breaks. Swipe horizontally to browse dates.")
                .font(.footnote).foregroundStyle(.secondary)
            Chart(orderedDates, id: \.self) { date in
                BarMark(
                    x: .value("Date", date, unit: .day),
                    y: .value("Walking minutes", totals[date] ?? 0)
                )
                .foregroundStyle(.teal)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                .accessibilityValue("\((totals[date] ?? 0).formatted(.number.precision(.fractionLength(1)))) walking minutes")
            }
            .chartYAxisLabel("Minutes")
            .chartYScale(domain: .automatic(includesZero: true))
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 14 * 24 * 60 * 60)
            .chartScrollPosition(initialX: Calendar.current.date(byAdding: .day, value: -13,
                to: orderedDates.last ?? Date()) ?? Date())
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 260)
            .accessibilityIdentifier("dailyWalkingMinutesChart")
        }
    }


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Total: \(store.periods.reduce(0) { $0 + $1.walkingMinutes }.formatted(.number.precision(.fractionLength(1)))) qualifying active minutes")
                    .font(.headline)
                if store.loaded {
                    Text("\(store.periods.count) qualifying periods").font(.title2.bold())
                    if store.periods.isEmpty {
                        ContentUnavailableView("No qualifying periods", systemImage: "figure.walk",
                            description: Text("No readable walks meet both thresholds. Check Steps access in Health → your profile → Apps → 元气农场. Health does not reveal whether read access was denied."))
                    }
                    if !store.periods.isEmpty {
                        walkingChart
                    }
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(dates, id: \.self) { date in
                            Text(date, format: .dateTime.year().month(.wide).day())
                                .font(.title3.bold()).padding(.top, 8)
                            Text("Date total: \((dailyMinutes[date] ?? 0).formatted(.number.precision(.fractionLength(1)))) walking minutes")
                                .font(.subheadline.bold())
                            ForEach(store.periods.filter { Calendar.current.isDate($0.start, inSameDayAs: date) }) { period in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(period.steps.formatted(.number.precision(.fractionLength(0)))) steps · \(period.walkingMinutes.formatted(.number.precision(.fractionLength(1)))) walking minutes")
                                        .font(.headline).monospacedDigit()
                                    Text("Start: \(period.start.formatted(.dateTime.month(.abbreviated).day().hour().minute().timeZone(.iso8601(.short))))")
                                    Text("End: \(period.end.formatted(.dateTime.month(.abbreviated).day().hour().minute().timeZone(.iso8601(.short))))")
                                }
                                .padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                    if let updated = store.updated {
                        Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

            }.padding(24)
        }
        .navigationTitle("Filtered")
        .navigationBarTitleDisplayMode(.inline)
    }
}
