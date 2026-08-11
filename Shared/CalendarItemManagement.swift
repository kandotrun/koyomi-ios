import Foundation

public enum CalendarEventReferenceError: Error, Equatable, Sendable {
    case notFound
    case ambiguous
}

public struct CalendarEventReference: Equatable, Sendable {
    public let occurrenceID: String
    public let eventIdentifier: String
    public let externalIdentifier: String?
    public let calendarID: String
    public let startDate: Date
    public let endDate: Date

    public init?(_ event: CalendarEvent) {
        let eventIdentifier = event.eventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let externalIdentifier = event.externalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !event.calendarID.isEmpty,
              !eventIdentifier.isEmpty || externalIdentifier?.isEmpty == false
        else { return nil }

        self.occurrenceID = EventOccurrenceID.make(
            eventIdentifier: eventIdentifier,
            externalIdentifier: externalIdentifier,
            startDate: event.startDate
        )
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier?.isEmpty == false ? externalIdentifier : nil
        self.calendarID = event.calendarID
        self.startDate = event.startDate
        self.endDate = event.endDate
    }

    public func matches(_ candidate: CalendarEvent) -> Bool {
        guard candidate.calendarID == calendarID,
              datesMatch(candidate.startDate, startDate),
              datesMatch(candidate.endDate, endDate)
        else { return false }

        if !eventIdentifier.isEmpty, candidate.eventIdentifier != eventIdentifier {
            return false
        }
        if let externalIdentifier,
           candidate.externalIdentifier != externalIdentifier {
            return false
        }

        let candidateID = EventOccurrenceID.make(
            eventIdentifier: candidate.eventIdentifier,
            externalIdentifier: candidate.externalIdentifier,
            startDate: candidate.startDate
        )
        return candidateID == occurrenceID
    }

    public func resolve(in candidates: [CalendarEvent]) throws -> CalendarEvent {
        let matches = candidates.filter(matches)
        guard !matches.isEmpty else { throw CalendarEventReferenceError.notFound }
        guard matches.count == 1 else { throw CalendarEventReferenceError.ambiguous }
        return matches[0]
    }

    private func datesMatch(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 0.001
    }
}

public enum CalendarMutationScope: Hashable, Sendable {
    case thisEvent
    case futureEvents
}

public struct CalendarCompletionUndoAction: Equatable, Sendable {
    public let previousCompletedValue: Bool
    public let scope: CalendarMutationScope

    public init(previousCompletedValue: Bool, scope: CalendarMutationScope) {
        self.previousCompletedValue = previousCompletedValue
        self.scope = scope
    }
}

public enum CalendarAllDayRange {
    public static func displayEndDate(
        forExclusiveEnd exclusiveEnd: Date,
        startDate: Date,
        calendar: Calendar
    ) -> Date {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: exclusiveEnd)
        guard end > start else { return start }
        return calendar.date(byAdding: .day, value: -1, to: end) ?? start
    }

    public static func exclusiveEndDate(
        forDisplayEnd displayEnd: Date,
        startDate: Date,
        calendar: Calendar
    ) -> Date {
        let start = calendar.startOfDay(for: startDate)
        let display = max(calendar.startOfDay(for: displayEnd), start)
        return calendar.date(byAdding: .day, value: 1, to: display)
            ?? display.addingTimeInterval(86_400)
    }
}

public enum CalendarDateMode: Hashable, Sendable {
    case exact
    case estimatedWindow
}

public enum CalendarEstimatedWindowStatus: Equatable, Sendable {
    case upcoming(daysUntilStart: Int)
    case withinWindow(daysUntilLatest: Int)
    case overdue(days: Int)
}

public struct CalendarEstimatedWindow: Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let centerDate: Date
    public let latestDate: Date
    public let bufferDays: Int

    private init(
        startDate: Date,
        endDate: Date,
        centerDate: Date,
        latestDate: Date,
        bufferDays: Int
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.centerDate = centerDate
        self.latestDate = latestDate
        self.bufferDays = bufferDays
    }

    public static func hasStoredWindowShape(
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let start = calendar.startOfDay(for: startDate)
        let latest = CalendarAllDayRange.displayEndDate(
            forExclusiveEnd: endDate,
            startDate: start,
            calendar: calendar
        )
        let span = calendar.dateComponents([.day], from: start, to: latest).day ?? 0
        return span >= 2 && span.isMultiple(of: 2)
    }

    public static func centered(
        on centerDate: Date,
        bufferDays: Int,
        calendar: Calendar = .current
    ) -> CalendarEstimatedWindow? {
        let bufferDays = max(bufferDays, 1)
        let center = calendar.startOfDay(for: centerDate)
        guard let start = calendar.date(byAdding: .day, value: -bufferDays, to: center),
              let latest = calendar.date(byAdding: .day, value: bufferDays, to: center),
              let end = calendar.date(byAdding: .day, value: 1, to: latest)
        else { return nil }
        return CalendarEstimatedWindow(
            startDate: start,
            endDate: end,
            centerDate: center,
            latestDate: latest,
            bufferDays: bufferDays
        )
    }

    public init?(event: CalendarEvent, calendar: Calendar = .current) {
        guard event.isEstimatedDateWindow,
              let window = Self.fromStoredRange(
                  startDate: event.startDate,
                  endDate: event.endDate,
                  calendar: calendar
              )
        else { return nil }
        self = window
    }

    public init?(event: PinnedEvent, calendar: Calendar = .current) {
        guard event.isEstimatedDateWindow,
              let window = Self.fromStoredRange(
                  startDate: event.startDate,
                  endDate: event.endDate,
                  calendar: calendar
              )
        else { return nil }
        self = window
    }

    private static func fromStoredRange(
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) -> CalendarEstimatedWindow? {
        guard hasStoredWindowShape(startDate: startDate, endDate: endDate, calendar: calendar) else {
            return nil
        }
        let start = calendar.startOfDay(for: startDate)
        let latest = CalendarAllDayRange.displayEndDate(
            forExclusiveEnd: endDate,
            startDate: start,
            calendar: calendar
        )
        let span = calendar.dateComponents([.day], from: start, to: latest).day ?? 0
        guard let center = calendar.date(byAdding: .day, value: span / 2, to: start) else {
            return nil
        }
        return CalendarEstimatedWindow(
            startDate: start,
            endDate: endDate,
            centerDate: center,
            latestDate: latest,
            bufferDays: span / 2
        )
    }

    public func status(
        at now: Date,
        calendar: Calendar = .current
    ) -> CalendarEstimatedWindowStatus {
        let today = calendar.startOfDay(for: now)
        if today < startDate {
            return .upcoming(daysUntilStart: dayDistance(from: today, to: startDate, calendar: calendar))
        }
        if today <= latestDate {
            return .withinWindow(daysUntilLatest: dayDistance(from: today, to: latestDate, calendar: calendar))
        }
        return .overdue(days: dayDistance(from: latestDate, to: today, calendar: calendar))
    }

    private func dayDistance(from start: Date, to end: Date, calendar: Calendar) -> Int {
        max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
    }
}

public enum CalendarEstimatedWindowText {
    public static func date(_ date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar: calendar, dateFormat: "yyyy年M月d日").string(from: date)
    }

    public static func range(
        _ window: CalendarEstimatedWindow,
        calendar: Calendar = .current
    ) -> String {
        let gregorian = gregorianCalendar(from: calendar)
        let startYear = gregorian.component(.year, from: window.startDate)
        let latestYear = gregorian.component(.year, from: window.latestDate)
        let start = date(window.startDate, calendar: calendar)
        let latestFormat = startYear == latestYear ? "M月d日" : "yyyy年M月d日"
        let latest = formatter(calendar: calendar, dateFormat: latestFormat).string(from: window.latestDate)
        return "\(start)〜\(latest)"
    }

    public static func buffer(days: Int) -> String {
        let days = max(days, 1)
        if days.isMultiple(of: 7) {
            return "各\(days / 7)週間"
        }
        return "各\(days)日"
    }

    public static func width(_ window: CalendarEstimatedWindow) -> String {
        let days = window.bufferDays * 2
        if days.isMultiple(of: 7) {
            return "幅\(days / 7)週間"
        }
        return "幅\(days)日"
    }

    private static func formatter(calendar: Calendar, dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = gregorianCalendar(from: calendar)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = dateFormat
        return formatter
    }

    private static func gregorianCalendar(from calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }
}

public enum CalendarItemDateSummary {
    public static func text(
        for event: CalendarEvent,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = locale
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = locale
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let startDate = dateFormatter.string(from: event.startDate)
        if event.isAllDay {
            let displayEnd = CalendarAllDayRange.displayEndDate(
                forExclusiveEnd: event.endDate,
                startDate: event.startDate,
                calendar: calendar
            )
            guard !calendar.isDate(event.startDate, inSameDayAs: displayEnd) else {
                return "\(startDate)・終日"
            }
            return "\(startDate)〜\(dateFormatter.string(from: displayEnd))・終日"
        }

        let startTime = timeFormatter.string(from: event.startDate)
        let endTime = timeFormatter.string(from: event.endDate)
        if calendar.isDate(event.startDate, inSameDayAs: event.endDate) {
            return "\(startDate) \(startTime)〜\(endTime)"
        }
        return "\(startDate) \(startTime)〜\(dateFormatter.string(from: event.endDate)) \(endTime)"
    }
}

public enum CalendarRecurrenceAccessibility {
    public static func selectionValue(isSelected: Bool) -> String {
        isSelected ? "選択済み" : "未選択"
    }
}

public enum CalendarRecurrenceFrequency: String, Codable, CaseIterable, Hashable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly
}

public enum CalendarRecurrenceWeekday: Int, Codable, CaseIterable, Hashable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
}

public struct CalendarRecurrenceRule: Codable, Equatable, Sendable {
    public let frequency: CalendarRecurrenceFrequency
    public let interval: Int
    public let weekdays: [CalendarRecurrenceWeekday]
    public let endDate: Date?
    public let occurrenceCount: Int?
    public let isFullyRepresentable: Bool

    public init(
        frequency: CalendarRecurrenceFrequency,
        interval: Int = 1,
        weekdays: [CalendarRecurrenceWeekday] = [],
        endDate: Date? = nil,
        occurrenceCount: Int? = nil,
        isFullyRepresentable: Bool = true
    ) {
        self.frequency = frequency
        self.interval = max(interval, 1)
        self.weekdays = weekdays
        self.endDate = endDate
        self.occurrenceCount = occurrenceCount
        self.isFullyRepresentable = isFullyRepresentable
    }

    private enum CodingKeys: String, CodingKey {
        case frequency
        case interval
        case weekdays
        case endDate
        case occurrenceCount
        case isFullyRepresentable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decode(CalendarRecurrenceFrequency.self, forKey: .frequency)
        interval = max(try container.decodeIfPresent(Int.self, forKey: .interval) ?? 1, 1)
        weekdays = try container.decodeIfPresent(
            [CalendarRecurrenceWeekday].self,
            forKey: .weekdays
        ) ?? []
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        occurrenceCount = try container.decodeIfPresent(Int.self, forKey: .occurrenceCount)
        isFullyRepresentable = try container.decodeIfPresent(
            Bool.self,
            forKey: .isFullyRepresentable
        ) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(interval, forKey: .interval)
        try container.encode(weekdays, forKey: .weekdays)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encodeIfPresent(occurrenceCount, forKey: .occurrenceCount)
        try container.encode(isFullyRepresentable, forKey: .isFullyRepresentable)
    }
}

public enum CalendarRecurrenceEditorPolicy {
    public static func ruleForSave(
        original: CalendarRecurrenceRule?,
        frequency: CalendarRecurrenceFrequency?,
        interval: Int,
        weekdays: [CalendarRecurrenceWeekday],
        endDate: Date?,
        occurrenceCount: Int?
    ) -> CalendarRecurrenceRule? {
        if let original, !original.isFullyRepresentable {
            return original
        }
        guard let frequency else { return nil }

        return CalendarRecurrenceRule(
            frequency: frequency,
            interval: interval,
            weekdays: frequency == .weekly ? weekdays : [],
            endDate: endDate,
            occurrenceCount: occurrenceCount
        )
    }
}

public enum CalendarAlarmOffsets {
    public static func equivalent(_ lhs: [TimeInterval], _ rhs: [TimeInterval]) -> Bool {
        lhs.sorted() == rhs.sorted()
    }
}

public enum CalendarRecurrenceSummary {
    public static func text(
        _ recurrence: CalendarRecurrenceRule,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let base: String
        if recurrence.interval == 1 {
            base = switch recurrence.frequency {
            case .daily: "毎日"
            case .weekly: "毎週"
            case .monthly: "毎月"
            case .yearly: "毎年"
            }
        } else {
            let unit = switch recurrence.frequency {
            case .daily: "日"
            case .weekly: "週"
            case .monthly: "か月"
            case .yearly: "年"
            }
            base = "\(recurrence.interval)\(unit)ごと"
        }

        var value = base
        if recurrence.frequency == .weekly, !recurrence.weekdays.isEmpty {
            let weekdays = recurrence.weekdays.map(weekdayTitle).joined(separator: "・")
            value += "（\(weekdays)）"
        }
        if let count = recurrence.occurrenceCount {
            value += "・\(count)回"
        }
        if let endDate = recurrence.endDate {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            value += "・\(formatter.string(from: endDate))まで"
        }
        return value
    }

    private static func weekdayTitle(_ weekday: CalendarRecurrenceWeekday) -> String {
        switch weekday {
        case .sunday: "日"
        case .monday: "月"
        case .tuesday: "火"
        case .wednesday: "水"
        case .thursday: "木"
        case .friday: "金"
        case .saturday: "土"
        }
    }
}

public struct CalendarItemDraft: Equatable, Sendable {
    public var kind: ManagedCalendarItemKind
    public var dateMode: CalendarDateMode
    public var readableTitle: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var tags: [String]
    public var isImportant: Bool
    public var isCompleted: Bool
    public var location: String?
    public var notes: String?
    public var alarmOffsets: [TimeInterval]
    public var recurrence: CalendarRecurrenceRule?

    public init(
        kind: ManagedCalendarItemKind,
        dateMode: CalendarDateMode = .exact,
        readableTitle: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarID: String,
        tags: [String] = [],
        isImportant: Bool = false,
        isCompleted: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        alarmOffsets: [TimeInterval] = [],
        recurrence: CalendarRecurrenceRule? = nil
    ) {
        self.kind = kind
        self.dateMode = dateMode
        self.readableTitle = readableTitle
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.tags = tags
        self.isImportant = isImportant
        self.isCompleted = isCompleted
        self.location = location
        self.notes = notes
        self.alarmOffsets = alarmOffsets
        self.recurrence = recurrence
    }

    public init(_ event: CalendarEvent) {
        let metadata = event.titleMetadata
        var reserved = Set(["タスク", "重要"].map(EventTitleMetadata.normalize))
        if event.isEstimatedDateWindow {
            reserved.insert(EventTitleMetadata.normalize("見込み"))
        }
        if event.managementKind == .task {
            reserved.insert(EventTitleMetadata.normalize("完了"))
        }
        self.init(
            kind: event.managementKind,
            dateMode: event.isEstimatedDateWindow ? .estimatedWindow : .exact,
            readableTitle: metadata.displayTitle,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: event.calendarID,
            tags: metadata.tags.filter { !reserved.contains(EventTitleMetadata.normalize($0)) },
            isImportant: metadata.containsTag("重要"),
            isCompleted: event.isCompletedTask,
            location: event.location,
            notes: event.notes,
            alarmOffsets: event.alarmOffsets,
            recurrence: event.recurrence
        )
    }

    public func hasValidDateModeShape(calendar: Calendar = .current) -> Bool {
        guard dateMode == .estimatedWindow else { return true }
        guard kind == .task, isAllDay, recurrence == nil else { return false }
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard calendar.isDate(startDate, equalTo: start, toGranularity: .second),
              calendar.isDate(endDate, equalTo: end, toGranularity: .second)
        else { return false }
        return CalendarEstimatedWindow.hasStoredWindowShape(
            startDate: start,
            endDate: end,
            calendar: calendar
        )
    }
}

public enum ManagedCalendarItemKind: Hashable, Sendable {
    case event
    case task
}

public struct EventTitleTagChange: Equatable, Sendable {
    public let adding: [String]
    public let removing: [String]

    public init(adding: [String], removing: [String]) {
        self.adding = adding
        self.removing = removing
    }
}

public enum EventTitleTagMutator {
    public static func replacingReadableText(in rawTitle: String, with readableTitle: String) -> String {
        let title = readableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagTokens = rawTitle
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { parsedTagToken(in: $0) != nil }
        return ([title] + tagTokens)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func applying(_ change: EventTitleTagChange, to rawTitle: String) -> String {
        let removals = Set(change.removing.compactMap(canonicalTag).map(EventTitleMetadata.normalize))
        var result = ""
        var index = rawTitle.startIndex

        while index < rawTitle.endIndex {
            if rawTitle[index].isWhitespace {
                result.append(rawTitle[index])
                index = rawTitle.index(after: index)
                continue
            }

            let tokenStart = index
            while index < rawTitle.endIndex, !rawTitle[index].isWhitespace {
                index = rawTitle.index(after: index)
            }
            let token = String(rawTitle[tokenStart..<index])
            if let parsedTag = parsedTagToken(in: token),
               removals.contains(EventTitleMetadata.normalize(parsedTag.tag)) {
                result.append(parsedTag.suffix)
            } else {
                result.append(token)
            }
        }

        var existing = Set(EventTitleMetadata.parse(result).tags.map(EventTitleMetadata.normalize))
        for tag in change.adding.compactMap(canonicalTag) {
            let normalized = EventTitleMetadata.normalize(tag)
            guard existing.insert(normalized).inserted else { continue }

            if let last = result.last, !last.isWhitespace {
                result.append(" ")
            }
            result.append("#\(tag)")
        }
        return result
    }

    static func canonicalTag(_ candidate: String) -> String? {
        var value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.first == "#" {
            value.removeFirst()
        }
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else { return nil }
        return value
    }

    private struct ParsedTagToken {
        let tag: String
        let suffix: String
    }

    private static func parsedTagToken(in token: String) -> ParsedTagToken? {
        guard token.first == "#" else { return nil }
        let punctuation = CharacterSet(charactersIn: "、。,.!?！？:：;；)]}）】」』…")
        var tag = String(token.dropFirst())
        var suffix = ""
        while let last = tag.last,
              last.unicodeScalars.allSatisfy({ punctuation.contains($0) }) {
            suffix.insert(last, at: suffix.startIndex)
            tag.removeLast()
        }
        guard !tag.isEmpty else { return nil }
        return ParsedTagToken(tag: tag, suffix: suffix)
    }
}

public enum PinnedEventDeletionPolicy {
    public static func remainingPins(
        afterDeleting event: CalendarEvent,
        scope: CalendarMutationScope,
        from pins: [PinnedEvent]
    ) -> [PinnedEvent] {
        switch scope {
        case .thisEvent:
            return pins.filter { $0.id != event.pinnedSnapshot.id }
        case .futureEvents:
            return pins.filter { pin in
                guard pin.startDate >= event.startDate else { return true }
                return !belongsToSameSeries(pin, as: event)
            }
        }
    }

    private static func belongsToSameSeries(_ pin: PinnedEvent, as event: CalendarEvent) -> Bool {
        let eventIdentifier = event.eventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !eventIdentifier.isEmpty, pin.eventIdentifier == eventIdentifier {
            return true
        }
        guard let externalIdentifier = event.externalIdentifier?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !externalIdentifier.isEmpty else {
            return false
        }
        return pin.externalIdentifier == externalIdentifier
    }
}

public enum ManagedCalendarTitle {
    public static func make(
        readableTitle: String,
        kind: ManagedCalendarItemKind,
        dateMode: CalendarDateMode = .exact,
        isImportant: Bool,
        isCompleted: Bool,
        tags: [String]
    ) -> String {
        let title = readableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var orderedTags: [String] = []
        var identities: Set<String> = []

        func append(_ candidate: String) {
            guard let tag = EventTitleTagMutator.canonicalTag(candidate) else { return }
            let normalized = EventTitleMetadata.normalize(tag)
            guard identities.insert(normalized).inserted else { return }
            orderedTags.append(tag)
        }

        if kind == .task { append("タスク") }
        if dateMode == .estimatedWindow { append("見込み") }
        if isImportant { append("重要") }
        if isCompleted { append("完了") }
        tags.forEach(append)

        guard !orderedTags.isEmpty else { return title }
        let suffix = orderedTags.map { "#\($0)" }.joined(separator: " ")
        return title.isEmpty ? suffix : "\(title) \(suffix)"
    }
}

extension CalendarEvent {
    public var managementKind: ManagedCalendarItemKind {
        titleMetadata.containsTag("タスク") ? .task : .event
    }

    public var isCompletedTask: Bool {
        managementKind == .task && titleMetadata.containsTag("完了")
    }

    public var isImportantItem: Bool {
        titleMetadata.containsTag("重要")
    }

    public var isEstimatedDateWindow: Bool {
        managementKind == .task
            && isAllDay
            && titleMetadata.containsTag("見込み")
            && CalendarEstimatedWindow.hasStoredWindowShape(
                startDate: startDate,
                endDate: endDate
            )
    }
}

extension PinnedEvent {
    public var isEstimatedDateWindow: Bool {
        titleMetadata.containsTag("タスク")
            && isAllDay
            && titleMetadata.containsTag("見込み")
            && CalendarEstimatedWindow.hasStoredWindowShape(
                startDate: startDate,
                endDate: endDate
            )
    }

    public var isOpenEstimatedTask: Bool {
        isEstimatedDateWindow
            && titleMetadata.containsTag("タスク")
            && !titleMetadata.containsTag("完了")
    }
}
