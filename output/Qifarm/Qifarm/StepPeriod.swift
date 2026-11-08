import Foundation

struct StepMinute {
    let start: Date
    let end: Date
    let steps: Double
}

struct StepPeriod: Identifiable {
    var id: Date { start }
    let start: Date
    var end: Date
    var steps: Double

    var breakSeconds: TimeInterval = 0
    var walkingMinutes: Double { (end.timeIntervalSince(start) - breakSeconds) / 60 }

    var averageStepsPerMinute: Double { elapsedMinutes > 0 ? steps / elapsedMinutes : 0 }

    var elapsedMinutes: Double { end.timeIntervalSince(start) / 60 }

    /// Rejoin query chunks without applying the five-minute merge or qualification rules.
    static func continuous(_ periods: [StepPeriod], calendar: Calendar = .current) -> [StepPeriod] {
        merge(periods, maximumBreak: 60, calendar: calendar)
    }

    static func grouped(_ periods: [StepPeriod], calendar: Calendar = .current) -> [StepPeriod] {
        merge(periods, maximumBreak: 5 * 60, calendar: calendar)
    }

    var isQualifying: Bool { walkingMinutes > 30 && averageStepsPerMinute > 60 }

    var filterExplanation: String {
        var reasons: [String] = []
        if walkingMinutes <= 30 { reasons.append("active time must exceed 30 minutes") }
        if averageStepsPerMinute <= 60 { reasons.append("cadence must exceed 60 steps per elapsed minute") }
        return reasons.isEmpty ? "Passed · active time > 30 minutes and cadence > 60 steps/elapsed min"
            : "Failed · " + reasons.joined(separator: "; ")
    }


    /// Merge first, then filter. Duration excludes breaks; cadence includes elapsed break time.
    static func qualifying(_ periods: [StepPeriod], calendar: Calendar = .current) -> [StepPeriod] {
        grouped(periods, calendar: calendar).filter(\.isQualifying)
    }

    private static func merge(_ periods: [StepPeriod], maximumBreak: TimeInterval,
                              calendar: Calendar) -> [StepPeriod] {
        var merged: [StepPeriod] = []
        for period in deduplicated(periods).sorted(by: { $0.start < $1.start }) {
            guard period.steps.isFinite, period.steps > 0, period.end > period.start else { continue }
            if let last = merged.last,
               calendar.isDate(last.start, inSameDayAs: period.start),
               period.start >= last.end,
               period.start.timeIntervalSince(last.end) < maximumBreak {
                merged[merged.count - 1].breakSeconds += period.start.timeIntervalSince(last.end) + period.breakSeconds
                merged[merged.count - 1].end = period.end
                merged[merged.count - 1].steps += period.steps
            } else {
                merged.append(period)
            }
        }
        return merged
    }

    static func deduplicated(_ periods: [StepPeriod]) -> [StepPeriod] {
        struct Key: Hashable { let start: Date; let end: Date }
        var records: [Key: StepPeriod] = [:]
        for period in periods { records[Key(start: period.start, end: period.end)] = period }
        return records.values.sorted { $0.start < $1.start }
    }

    /// Input comes from nonoverlapping HealthKit minute buckets.
    static func group(_ minutes: [StepMinute], calendar: Calendar = .current) -> [StepPeriod] {
        var periods: [StepPeriod] = []
        var current: StepPeriod?
        for minute in minutes.sorted(by: { $0.start < $1.start }) {
            guard minute.steps.isFinite, minute.steps > 0, minute.end > minute.start else {
                if let period = current { periods.append(period) }
                current = nil
                continue
            }
            if var period = current,
               calendar.isDate(period.start, inSameDayAs: minute.start),
               minute.start >= period.end,
               minute.start.timeIntervalSince(period.end) < 60 {
                period.breakSeconds += minute.start.timeIntervalSince(period.end)
                period.end = minute.end
                period.steps += minute.steps
                current = period
            } else {
                if let period = current { periods.append(period) }
                current = StepPeriod(start: minute.start, end: minute.end, steps: minute.steps)
            }
        }
        if let period = current { periods.append(period) }
        return periods
    }
}

// Qifarm interchange format for HealthKit-synced AllTrails workouts.
struct TrailActivity: Codable, Identifiable {
    let id: String
    let name: String
    let start: Date
    let end: Date
    let movingMinutes: Double
    let distanceMeters: Double?
    let elevationGainMeters: Double?
    var sourceName: String? = nil
    var sourceBundleIdentifier: String? = nil

    static func deduplicated(_ activities: [TrailActivity]) -> [TrailActivity] {
        var records: [String: TrailActivity] = [:]
        for activity in activities { records[activity.id] = activity }
        return records.values.sorted { $0.start > $1.start }
    }

    var averageSpeedKmh: Double? {
        guard let distanceMeters, distanceMeters.isFinite, distanceMeters >= 0,
              movingMinutes.isFinite, movingMinutes > 0,
              end > start, movingMinutes <= end.timeIntervalSince(start) / 60 + 0.0001 else { return nil }
        let speed = distanceMeters / 1000 / (movingMinutes / 60)
        return speed.isFinite ? speed : nil
    }
    var isQualifying: Bool {
        guard let speed = averageSpeedKmh else { return false }
        return speed >= 2 && speed <= 5
    }
    var filterExplanation: String {
        guard let speed = averageSpeedKmh else { return "Failed · missing distance or invalid duration" }
        if speed < 2 { return "Failed · average speed below 2 km/h" }
        if speed > 5 { return "Failed · average speed above 5 km/h" }
        return "Passed · average speed between 2 and 5 km/h"
    }
}

struct TrailExport: Codable {
    let version: Int
    let source: String
    let activities: [TrailActivity]

    static func read(_ data: Data, now: Date = Date()) throws -> [TrailActivity] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw TrailImportError.invalid }
            return date
        }
        guard data.count <= 50 * 1024 * 1024 else { throw TrailImportError.invalid }
        let export: TrailExport
        do { export = try decoder.decode(TrailExport.self, from: data) }
        catch { throw TrailImportError.unsupported }
        guard export.version == 1, export.source == "alltrails" else { throw TrailImportError.unsupported }
        var ids = Set<String>()
        for a in export.activities {
            guard !a.id.isEmpty, !a.name.isEmpty, ids.insert(a.id).inserted,
                  a.end > a.start, a.end <= now,
                  a.movingMinutes.isFinite, a.movingMinutes >= 0,
                  a.movingMinutes <= a.end.timeIntervalSince(a.start) / 60 + 0.0001,
                  a.elevationGainMeters.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  a.distanceMeters.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw TrailImportError.invalid }
        }
        return export.activities.sorted { $0.start > $1.start }
    }
}

enum TrailImportError: LocalizedError {
    case invalid, unsupported
    var errorDescription: String? {
        switch self {
        case .invalid: return "Invalid activity data. Check times, moving minutes, distance, elevation, and duplicate IDs."
        case .unsupported: return "This response is not a supported activity data file. AllTrails profile HTML cannot be imported. Use an AllTrails JSON file exported from 元气农场."
        }
    }
}


enum HealthTrailWorkout {
    static func isAllTrails(sourceName: String, bundleIdentifier: String) -> Bool {
        sourceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "alltrails"
            || bundleIdentifier.lowercased().split(separator: ".").contains("alltrails")
    }
}


// Confirmation returns to the app, but never signs in from URL-supplied tokens.
// The user authenticates with their email/password after confirming their email.
enum AuthCallback {
    static let redirectURL = "qifarm://auth/callback"
    static var signupPath: String {
        var components = URLComponents()
        components.path = "/auth/v1/signup"
        components.queryItems = [URLQueryItem(name: "redirect_to", value: redirectURL)]
        return components.string!
    }
    static func message(for url: URL) -> String? {
        guard url.scheme?.lowercased() == "qifarm", url.host?.lowercased() == "auth",
              url.path == "/callback", url.user == nil, url.password == nil, url.port == nil else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let fragment = URLComponents(string: "?" + (url.fragment ?? ""))?.queryItems ?? []
        if (query + fragment).contains(where: { $0.name == "error" || $0.name == "error_code" }) {
            return "The confirmation link could not be completed. It may have expired or already been used. Try logging in; if needed, request a new confirmation email from Supabase."
        }
        return "Returned from email confirmation. Log in with your email and password to continue."
    }
}


enum AuthenticationOutcome {
    case signedIn, registered, alreadyRegistered, failed
}

enum RegistrationResponse {
    static func isDuplicate(_ response: [String: Any]) -> Bool {
        let user = response["user"] as? [String: Any] ?? response
        // Supabase may return an obfuscated user with an explicitly empty identities array.
        // Missing identities alone does not prove an account already exists.
        if let identities = user["identities"] as? [Any] { return identities.isEmpty }
        return false
    }
    static func isDuplicateError(code: String?, message: String) -> Bool {
        if ["user_already_exists", "email_exists"].contains(code ?? "") { return true }
        let lower = message.lowercased()
        return lower.contains("already registered") || lower.contains("already been registered")
    }
}


enum SnapshotError: LocalizedError {
    case unsupportedSource, duplicateSource, invalidHistory
    var errorDescription: String? {
        switch self {
        case .unsupportedSource: return "The saved account contains an unsupported source."
        case .duplicateSource: return "The cloud response contains a duplicate data source."
        case .invalidHistory: return "Saved step history contains invalid or overlapping periods."
        }
    }
}

struct StepHistoryArchive {
    static func read(_ data: Data) throws -> [StepPeriod] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["version"] as? Int == 1, let rows = root["periods"] as? [[String: Any]] else {
            throw SnapshotError.invalidHistory
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basic = ISO8601DateFormatter()
        func date(_ text: String) -> Date? { formatter.date(from: text) ?? basic.date(from: text) }
        let periods: [StepPeriod] = try rows.map { row in
            guard let startText = row["start"] as? String, let endText = row["end"] as? String,
                  let start = date(startText), let end = date(endText), end > start,
                  let steps = row["steps"] as? Double, steps.isFinite, steps >= 0,
                  let breaks = row["breakSeconds"] as? Double, breaks.isFinite, breaks >= 0,
                  breaks < end.timeIntervalSince(start) else { throw SnapshotError.invalidHistory }
            return StepPeriod(start: start, end: end, steps: steps, breakSeconds: breaks)
        }
        let unique = StepPeriod.deduplicated(periods)
        for index in unique.indices.dropFirst() {
            guard unique[index].start >= unique[index - 1].end else { throw SnapshotError.invalidHistory }
        }
        return unique
    }
}


struct QualifiedActivityInterval {
    let start: Date
    let end: Date
    let minutes: Double
}

enum ActivityTotals {
    /// Summary records do not locate each pause. Distribute active time across its
    /// interval, and take the highest active fraction where sources overlap.
    static func uniqueMinutes(_ intervals: [QualifiedActivityInterval]) -> Double {
        let valid = intervals.filter { $0.end > $0.start && $0.minutes.isFinite && $0.minutes > 0 }
        var events: [Date: [(Double, Int)]] = [:]
        for interval in valid {
            let fraction = min(1, interval.minutes * 60 / interval.end.timeIntervalSince(interval.start))
            events[interval.start, default: []].append((fraction, 1))
            events[interval.end, default: []].append((fraction, -1))
        }
        let boundaries = events.keys.sorted()
        var active: [Double: Int] = [:]
        var previous: Date?
        var total = 0.0
        for boundary in boundaries {
            if let previous { total += boundary.timeIntervalSince(previous) / 60 * (active.keys.max() ?? 0) }
            for (fraction, change) in events[boundary] ?? [] {
                let count = (active[fraction] ?? 0) + change
                if count <= 0 { active.removeValue(forKey: fraction) } else { active[fraction] = count }
            }
            previous = boundary
        }
        return total
    }
}

struct FarmPlace: Codable, Equatable {
    var country = ""
    var province = ""
    var city = ""
    init(country: String = "", province: String = "", city: String = "") {
        self.country = country; self.province = province; self.city = city
    }
    init(storedValue: String) {
        if let data = storedValue.data(using: .utf8), let place = try? JSONDecoder().decode(FarmPlace.self, from: data) {
            self = place
        } else if Self.isLegacyCoordinate(storedValue) {
            self.init()
        } else {
            let parts = storedValue.split(separator: ",", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 3 { self.init(country: parts[0], province: parts[1], city: parts[2]) }
            else if parts.count == 2 { self.init(province: parts[0], city: parts[1]) }
            else { self.init(city: storedValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }
    var displayValue: String {
        [country, province, city].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
    var storedValue: String {
        guard !displayValue.isEmpty else { return "" }
        return (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? ""
    }
    static func isLegacyCoordinate(_ text: String) -> Bool {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]) else { return false }
        return (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}
