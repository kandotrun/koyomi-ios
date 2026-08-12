import Foundation

public enum PinnedRecurrenceExpander {
    public static let defaultFutureOccurrenceLimit = 32
    private static let maximumCatchUpIterations = 100_000

    public static func expandedPins(
        from pins: [PinnedEvent],
        at referenceDate: Date = .now,
        calendar: Calendar = .current,
        futureOccurrenceLimit: Int = defaultFutureOccurrenceLimit
    ) -> [PinnedEvent] {
        guard futureOccurrenceLimit > 0 else { return pins }

        var expanded = pins
        let recurringBySeries = Dictionary(grouping: pins.compactMap { pin -> PinnedEvent? in
            guard let recurrence = pin.recurrence,
                  recurrence.isFullyRepresentable,
                  recurrence.occurrenceCount == nil,
                  pin.recurrenceSeriesIdentifier?.isEmpty == false,
                  pin.recurrenceAnchorDate != nil,
                  pin.recurrenceValidatedThroughDate != nil
            else { return nil }
            return pin
        }) { $0.recurrenceSeriesIdentifier! }

        for series in recurringBySeries.values {
            guard let template = series.max(by: { $0.startDate < $1.startDate }),
                  let recurrence = template.recurrence,
                  let anchorDate = template.recurrenceAnchorDate,
                  let validatedThroughDate = template.recurrenceValidatedThroughDate
            else { continue }
            var recurrenceCalendar = calendar
            if let identifier = template.recurrenceTimeZoneIdentifier,
               let timeZone = TimeZone(identifier: identifier) {
                recurrenceCalendar.timeZone = timeZone
            }

            var cursor = template
            var futureCount = Set(
                series.lazy
                    .filter { $0.endDate > referenceDate }
                    .map(\.id)
            ).count
            var iterationCount = 0
            while futureCount < futureOccurrenceLimit,
                  iterationCount < maximumCatchUpIterations {
                iterationCount += 1
                guard let nextStart = nextStartDate(
                    after: cursor.startDate,
                    recurrence: recurrence,
                    anchorDate: anchorDate,
                    calendar: recurrenceCalendar
                ) else { break }
                guard nextStart <= validatedThroughDate else { break }
                if let endDate = recurrence.endDate, nextStart > endDate { break }

                var next = template
                next.startDate = nextStart
                next.endDate = occurrenceEndDate(
                    startDate: nextStart,
                    template: template,
                    calendar: recurrenceCalendar
                )
                next.id = EventOccurrenceID.make(
                    eventIdentifier: next.eventIdentifier,
                    externalIdentifier: next.externalIdentifier,
                    startDate: nextStart
                )
                cursor = next

                guard next.endDate > referenceDate else { continue }
                expanded.append(next)
                futureCount += 1
            }
        }

        var uniqueByID: [String: PinnedEvent] = [:]
        for pin in expanded {
            uniqueByID[pin.id] = pin
        }
        return uniqueByID.values.sorted {
            if $0.startDate == $1.startDate { return $0.id < $1.id }
            return $0.startDate < $1.startDate
        }
    }

    static func validatedThroughDate(
        for events: [CalendarEvent],
        in validationInterval: DateInterval,
        calendar: Calendar = .current
    ) -> Date? {
        let sorted = events.filter {
            $0.startDate >= validationInterval.start
                && $0.startDate < validationInterval.end
        }.sorted {
            if $0.startDate == $1.startDate { return $0.id < $1.id }
            return $0.startDate < $1.startDate
        }
        guard let template = sorted.first(where: {
            $0.isPinned && $0.isRecurring && $0.recurrence != nil
        }),
              let recurrence = template.recurrence,
              recurrence.isFullyRepresentable,
              recurrence.occurrenceCount == nil
        else { return nil }
        let series = sorted.filter { $0.startDate >= template.startDate }

        var recurrenceCalendar = calendar
        if let identifier = template.recurrenceTimeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            recurrenceCalendar.timeZone = timeZone
        }
        let anchorDate = template.startDate
        var expectedStart = template.startDate
        var eventIndex = 0
        var validatedThrough: Date?
        var iterationCount = 0
        while expectedStart < validationInterval.end {
            if let recurrenceEndDate = recurrence.endDate,
               expectedStart > recurrenceEndDate {
                break
            }
            iterationCount += 1
            guard iterationCount <= maximumCatchUpIterations,
                  eventIndex < series.count
            else { return nil }
            let event = series[eventIndex]
            guard abs(expectedStart.timeIntervalSince(event.startDate)) < 0.001,
                  matchesTemplate(
                    event,
                    template: template,
                    recurrence: recurrence,
                    calendar: recurrenceCalendar
                  )
            else { return nil }
            validatedThrough = event.startDate
            eventIndex += 1
            guard let next = nextStartDate(
                after: expectedStart,
                recurrence: recurrence,
                anchorDate: anchorDate,
                calendar: recurrenceCalendar
            ), next > expectedStart else { return nil }
            expectedStart = next
        }
        guard eventIndex == series.count else { return nil }
        return validatedThrough
    }

    private static func matchesTemplate(
        _ event: CalendarEvent,
        template: CalendarEvent,
        recurrence: CalendarRecurrenceRule,
        calendar: Calendar
    ) -> Bool {
        event.isPinned
            && event.isRecurring
            && event.title == template.title
            && event.location == template.location
            && event.isAllDay == template.isAllDay
            && event.recurrence == recurrence
            && event.recurrenceTimeZoneIdentifier == template.recurrenceTimeZoneIdentifier
            && durationsMatch(event, template: template, calendar: calendar)
    }

    private static func durationsMatch(
        _ event: CalendarEvent,
        template: CalendarEvent,
        calendar: Calendar
    ) -> Bool {
        if event.isAllDay {
            let eventDays = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: event.startDate),
                to: calendar.startOfDay(for: event.endDate)
            ).day
            let templateDays = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: template.startDate),
                to: calendar.startOfDay(for: template.endDate)
            ).day
            return eventDays == templateDays
        }
        return abs(
            event.endDate.timeIntervalSince(event.startDate)
                - template.endDate.timeIntervalSince(template.startDate)
        ) < 0.001
    }

    private static func nextStartDate(
        after date: Date,
        recurrence: CalendarRecurrenceRule,
        anchorDate: Date,
        calendar: Calendar
    ) -> Date? {
        switch recurrence.frequency {
        case .daily:
            calendar.date(byAdding: .day, value: recurrence.interval, to: date)
        case .monthly:
            nextAnchoredStartDate(
                after: date,
                anchorDate: anchorDate,
                component: .month,
                interval: recurrence.interval,
                calendar: calendar
            )
        case .yearly:
            nextAnchoredStartDate(
                after: date,
                anchorDate: anchorDate,
                component: .year,
                interval: recurrence.interval,
                calendar: calendar
            )
        case .weekly:
            nextWeeklyStartDate(
                after: date,
                recurrence: recurrence,
                anchorDate: anchorDate,
                calendar: calendar
            )
        }
    }

    private static func nextAnchoredStartDate(
        after date: Date,
        anchorDate: Date,
        component: Calendar.Component,
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        let anchorDay = calendar.component(.day, from: anchorDate)
        let anchorMonth = calendar.component(.month, from: anchorDate)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: anchorDate)
        guard let anchorPeriodStart = periodStart(
            containing: anchorDate,
            component: component,
            calendar: calendar
        ) else { return nil }

        for ordinal in 1...maximumCatchUpIterations {
            let (periodOffset, overflow) = ordinal.multipliedReportingOverflow(by: interval)
            guard !overflow,
                  let targetPeriod = calendar.date(
                    byAdding: component,
                    value: periodOffset,
                    to: anchorPeriodStart
                  )
            else { return nil }

            let target = calendar.dateComponents([.era, .year, .month], from: targetPeriod)
            var candidateComponents = DateComponents()
            candidateComponents.calendar = calendar
            candidateComponents.timeZone = calendar.timeZone
            candidateComponents.era = target.era
            candidateComponents.year = target.year
            candidateComponents.month = component == .year ? anchorMonth : target.month
            candidateComponents.day = anchorDay
            candidateComponents.hour = time.hour
            candidateComponents.minute = time.minute
            candidateComponents.second = time.second
            candidateComponents.nanosecond = time.nanosecond

            guard let candidate = calendar.date(from: candidateComponents),
                  hasExpectedDateComponents(
                    candidate,
                    expected: candidateComponents,
                    calendar: calendar
                  )
            else { continue }
            if candidate > date { return candidate }
        }
        return nil
    }

    private static func periodStart(
        containing date: Date,
        component: Calendar.Component,
        calendar: Calendar
    ) -> Date? {
        let values = calendar.dateComponents([.era, .year, .month], from: date)
        var start = DateComponents()
        start.calendar = calendar
        start.timeZone = calendar.timeZone
        start.era = values.era
        start.year = values.year
        start.month = component == .year ? 1 : values.month
        start.day = 1
        return calendar.date(from: start)
    }

    private static func hasExpectedDateComponents(
        _ date: Date,
        expected: DateComponents,
        calendar: Calendar
    ) -> Bool {
        let actual = calendar.dateComponents(
            [.era, .year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return actual.era == expected.era
            && actual.year == expected.year
            && actual.month == expected.month
            && actual.day == expected.day
            && actual.hour == expected.hour
            && actual.minute == expected.minute
            && actual.second == expected.second
    }

    private static func nextWeeklyStartDate(
        after date: Date,
        recurrence: CalendarRecurrenceRule,
        anchorDate: Date,
        calendar: Calendar
    ) -> Date? {
        let weekdays = Set(
            recurrence.weekdays.isEmpty
                ? [CalendarRecurrenceWeekday(rawValue: calendar.component(.weekday, from: anchorDate))].compactMap { $0 }
                : recurrence.weekdays
        )
        guard !weekdays.isEmpty,
              let anchorWeek = calendar.dateInterval(of: .weekOfYear, for: anchorDate)?.start
        else { return nil }

        let (maximumDays, overflow) = recurrence.interval.multipliedReportingOverflow(by: 7)
        guard !overflow, maximumDays > 0, maximumDays <= maximumCatchUpIterations else { return nil }

        for offset in 1...maximumDays {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date),
                  let candidateWeek = calendar.dateInterval(of: .weekOfYear, for: candidate)?.start
            else { continue }
            let weekDistance = calendar.dateComponents(
                [.weekOfYear],
                from: anchorWeek,
                to: candidateWeek
            ).weekOfYear ?? -1
            guard weekDistance >= 0,
                  weekDistance.isMultiple(of: recurrence.interval),
                  let weekday = CalendarRecurrenceWeekday(
                      rawValue: calendar.component(.weekday, from: candidate)
                  ),
                  weekdays.contains(weekday)
            else { continue }
            return candidate
        }
        return nil
    }

    private static func occurrenceEndDate(
        startDate: Date,
        template: PinnedEvent,
        calendar: Calendar
    ) -> Date {
        guard template.isAllDay else {
            return startDate.addingTimeInterval(max(template.endDate.timeIntervalSince(template.startDate), 0))
        }
        let startDay = calendar.startOfDay(for: template.startDate)
        let endDay = calendar.startOfDay(for: template.endDate)
        let dayCount = max(calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 1, 1)
        return calendar.date(byAdding: .day, value: dayCount, to: calendar.startOfDay(for: startDate))
            ?? startDate.addingTimeInterval(TimeInterval(dayCount) * 86_400)
    }
}
