import Foundation

/// A partially typed `MMDDHHMM` stamp. Any component may be missing until the
/// user finishes typing; `isValid` only rejects out-of-range values, and a
/// calendar-invalid date (e.g. Feb 30) fails later when it is built.
public struct NumericDateStamp: Equatable {
    public var month: Int?
    public var day: Int?
    public var hour: Int?
    public var minute: Int?

    public init(month: Int? = nil, day: Int? = nil, hour: Int? = nil, minute: Int? = nil) {
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
    }

    public var hasDate: Bool { month != nil && day != nil }
    public var hasTime: Bool { hour != nil }
    public var isComplete: Bool { hasDate && minute != nil }

    public var isValid: Bool {
        if let m = month, !(1...12).contains(m) { return false }
        if let d = day, !(1...31).contains(d) { return false }
        if let h = hour, !(0...23).contains(h) { return false }
        if let n = minute, !(0...59).contains(n) { return false }
        return true
    }
}

/// Parses the compact numeric date entry (`MMDDHHMM`, 24 h) used by the capture
/// overlay and the item editor. Pure and side-effect free so it can be tested
/// without a view.
public enum NumericDateParser {
    public static let maxDigits = 8
    /// How many days before today a typed date may fall and still be read as
    /// this year. Anything older is treated as next year's occurrence.
    public static let graceDays = 3

    /// Keeps only digits, capped at `maxDigits`.
    public static func sanitize(_ raw: String) -> String {
        String(raw.filter(\.isNumber).prefix(maxDigits))
    }

    /// Reads the leading digits in `MM` `DD` `HH` `MM` order.
    public static func parse(_ raw: String) -> NumericDateStamp {
        let digits = Array(sanitize(raw))
        func slice(_ start: Int, _ length: Int) -> Int? {
            guard digits.count >= start + length else { return nil }
            return Int(String(digits[start..<start + length]))
        }
        return NumericDateStamp(
            month: slice(0, 2),
            day: slice(2, 2),
            hour: slice(4, 2),
            minute: slice(6, 2)
        )
    }

    /// Builds a concrete date from a full stamp. When `rollForward` is true and
    /// the date is clearly in the past — more than `graceDays` before today — it
    /// advances to the next year so typed dates always mean the next upcoming
    /// occurrence. Dates within the grace window (and earlier times today) are
    /// kept: typed times default to midnight, so rolling a near date forward
    /// would silently jump a whole year. Returns the date and the year used.
    public static func date(
        from stamp: NumericDateStamp,
        year: Int,
        now: Date = Date(),
        rollForward: Bool = true,
        calendar: Calendar = .current
    ) -> (date: Date, year: Int)? {
        guard stamp.isValid, let month = stamp.month, let day = stamp.day else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = stamp.hour ?? 0
        comps.minute = stamp.minute ?? 0
        comps.second = 0
        guard var result = calendar.date(from: comps) else { return nil }

        // Calendar normalizes overflow (Feb 30 → Mar 2); reject anything that
        // does not round-trip so impossible dates are reported as invalid.
        let check = calendar.dateComponents([.month, .day, .hour, .minute], from: result)
        guard check.month == month,
              check.day == day,
              check.hour == (stamp.hour ?? 0),
              check.minute == (stamp.minute ?? 0) else { return nil }

        var resolvedYear = year
        if rollForward,
           year == calendar.component(.year, from: now),
           let cutoff = calendar.date(byAdding: .day, value: -graceDays,
                                      to: calendar.startOfDay(for: now)),
           result < cutoff,
           let bumped = calendar.date(byAdding: .year, value: 1, to: result) {
            result = bumped
            resolvedYear = calendar.component(.year, from: bumped)
        }
        return (result, resolvedYear)
    }
}
