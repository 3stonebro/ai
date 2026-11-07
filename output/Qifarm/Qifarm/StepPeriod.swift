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

    var averageStepsPerMinute: Double { walkingMinutes > 0 ? steps / walkingMinutes : 0 }

    var elapsedMinutes: Double { end.timeIntervalSince(start) / 60 }

    /// Rejoin query chunks without applying the five-minute merge or qualification rules.
    static func continuous(_ periods: [StepPeriod], calendar: Calendar = .current) -> [StepPeriod] {
        merge(periods, maximumBreak: 60, calendar: calendar)
    }

    static func grouped(_ periods: [StepPeriod], calendar: Calendar = .current) -> [StepPeriod] {
        merge(periods, maximumBreak: 5 * 60, calendar: calendar)
    }

    var isQualifying: Bool { walkingMinutes > 30 && averageStepsPerMinute > 60 }

    /// Merge first, then filter. Both duration and cadence use active time excluding breaks.
    static func qualifying(_ periods: [StepPeriod], calendar: Calendar = .current) -> [StepPeriod] {
        grouped(periods, calendar: calendar).filter(\.isQualifying)
    }

    private static func merge(_ periods: [StepPeriod], maximumBreak: TimeInterval,
                              calendar: Calendar) -> [StepPeriod] {
        var merged: [StepPeriod] = []
        for period in periods.sorted(by: { $0.start < $1.start }) {
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
