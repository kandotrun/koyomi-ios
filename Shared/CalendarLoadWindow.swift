import Foundation

public enum CalendarLoadWindow {
    public static func interval(
        around date: Date,
        calendar: Calendar = .current,
        monthsBefore: Int = 1,
        monthsAfter: Int = 18
    ) -> DateInterval? {
        let selectedDay = calendar.startOfDay(for: date)
        guard
            let start = calendar.date(
                byAdding: .month,
                value: -max(0, monthsBefore),
                to: selectedDay
            ),
            let end = calendar.date(
                byAdding: .month,
                value: max(0, monthsAfter),
                to: selectedDay
            ),
            end > start
        else { return nil }

        return DateInterval(start: start, end: end)
    }

    public static func contains(
        day: Date,
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return false
        }
        return dayStart >= interval.start && nextDayStart <= interval.end
    }
}
