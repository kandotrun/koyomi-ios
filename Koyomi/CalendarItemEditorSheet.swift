import SwiftUI

enum CalendarItemEditorPurpose {
    case create(ManagedCalendarItemKind)
    case createEstimatedTask
    case edit(CalendarEvent)
    case duplicate(CalendarEvent)
}

struct CalendarItemEditorContext: Identifiable {
    let id = UUID()
    let purpose: CalendarItemEditorPurpose

    var originalEvent: CalendarEvent? {
        if case let .edit(event) = purpose { return event }
        return nil
    }

    var navigationTitle: String {
        switch purpose {
        case let .create(kind): kind == .task ? "タスクを追加" : "予定を追加"
        case .createEstimatedTask: "見込みタスクを追加"
        case .edit: "編集"
        case .duplicate: "複製"
        }
    }
}

struct CalendarItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let context: CalendarItemEditorContext
    let calendars: [CalendarDescriptor]
    let availableTags: [String]
    let onSave: (CalendarItemDraft, CalendarMutationScope) -> CalendarEvent?

    @State private var draft: CalendarItemDraft
    @State private var estimatedCenterDate: Date
    @State private var estimatedBufferDays: Int
    @State private var scope: CalendarMutationScope = .thisEvent
    @State private var recurrenceFrequency: CalendarRecurrenceFrequency?
    @State private var recurrenceInterval: Int
    @State private var recurrenceWeekdays: Set<CalendarRecurrenceWeekday>
    @State private var recurrenceEnd: RecurrenceEndChoice
    @State private var recurrenceEndDate: Date
    @State private var recurrenceCount: Int
    @State private var saveError: String?

    private static let alarmOptions = [
        AlarmOption(offset: 0, title: "開始時刻"),
        AlarmOption(offset: -300, title: "5分前"),
        AlarmOption(offset: -900, title: "15分前"),
        AlarmOption(offset: -1_800, title: "30分前"),
        AlarmOption(offset: -3_600, title: "1時間前"),
        AlarmOption(offset: -86_400, title: "1日前")
    ]

    init(
        context: CalendarItemEditorContext,
        calendars: [CalendarDescriptor],
        availableTags: [String] = [],
        selectedDate: Date,
        calendar: Calendar = .current,
        now: Date = .now,
        onSave: @escaping (CalendarItemDraft, CalendarMutationScope) -> CalendarEvent?
    ) {
        self.context = context
        self.calendars = calendars.filter(\.allowsContentModifications)
        self.availableTags = availableTags
        self.onSave = onSave

        let initial = Self.initialDraft(
            for: context.purpose,
            writableCalendars: self.calendars,
            selectedDate: selectedDate,
            calendar: calendar,
            now: now
        )
        _draft = State(initialValue: initial)
        let initialWindow: CalendarEstimatedWindow?
        switch context.purpose {
        case let .edit(event), let .duplicate(event):
            initialWindow = CalendarEstimatedWindow(event: event, calendar: calendar)
        case .createEstimatedTask:
            let center = calendar.date(
                byAdding: .month,
                value: 1,
                to: calendar.startOfDay(for: selectedDate)
            ) ?? selectedDate
            initialWindow = CalendarEstimatedWindow.centered(on: center, bufferDays: 14, calendar: calendar)
        case .create:
            initialWindow = nil
        }
        _estimatedCenterDate = State(initialValue: initialWindow?.centerDate ?? initial.startDate)
        _estimatedBufferDays = State(initialValue: initialWindow?.bufferDays ?? 14)
        _recurrenceFrequency = State(initialValue: initial.recurrence?.frequency)
        _recurrenceInterval = State(initialValue: initial.recurrence?.interval ?? 1)
        _recurrenceWeekdays = State(initialValue: Set(initial.recurrence?.weekdays ?? []))
        if initial.recurrence?.occurrenceCount != nil {
            _recurrenceEnd = State(initialValue: .count)
        } else if initial.recurrence?.endDate != nil {
            _recurrenceEnd = State(initialValue: .date)
        } else {
            _recurrenceEnd = State(initialValue: .never)
        }
        _recurrenceEndDate = State(
            initialValue: initial.recurrence?.endDate
                ?? calendar.date(byAdding: .month, value: 1, to: initial.startDate)
                ?? initial.startDate
        )
        _recurrenceCount = State(initialValue: initial.recurrence?.occurrenceCount ?? 10)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                Form {
                Section("種類とタイトル") {
                    Picker("種類", selection: $draft.kind) {
                        Label("予定", systemImage: "calendar").tag(ManagedCalendarItemKind.event)
                        Label("タスク", systemImage: "checkmark.circle").tag(ManagedCalendarItemKind.task)
                    }
                    .pickerStyle(.segmented)

                    TextField("タイトル（必須）", text: $draft.readableTitle)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("calendar-item-title")

                    Toggle("重要", isOn: $draft.isImportant)
                    if draft.kind == .task {
                        Toggle("完了", isOn: $draft.isCompleted)
                            .accessibilityIdentifier("calendar-item-completed")
                    }
                }

                Section("日程") {
                    if context.originalEvent?.isRecurring == true {
                        Label(
                            "繰り返し予定の日程は「日時確定」のまま編集します。",
                            systemImage: "repeat"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        Picker("日程", selection: $draft.dateMode) {
                            Text("日時確定").tag(CalendarDateMode.exact)
                            Text("だいたい").tag(CalendarDateMode.estimatedWindow)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("calendar-item-date-mode")
                    }

                    if draft.dateMode == .estimatedWindow {
                        Label(
                            "具体的な日付が未確定のものを、目安日と前後の幅で管理します。保存すると自動でピン留めし、期間を過ぎても完了まで表示します。",
                            systemImage: "calendar.badge.clock"
                        )
                        .font(.footnote)
                        .foregroundStyle(.primary.opacity(0.72))

                        DatePicker(
                            "目安日",
                            selection: $estimatedCenterDate,
                            displayedComponents: .date
                        )
                        .accessibilityIdentifier("calendar-item-estimated-center")

                        Stepper(
                            "目安日の前後：\(estimatedBufferTitle)",
                            value: $estimatedBufferDays,
                            in: 1...90
                        )
                        .accessibilityIdentifier("calendar-item-estimated-buffer")
                        .accessibilityLabel("目安日の前後の幅")
                        .accessibilityValue(estimatedBufferTitle)
                        .accessibilityHint("1日ずつ調整します")

                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                "見込み期間：\(estimatedRangeText)（\(estimatedWidthText)）",
                                systemImage: "calendar.badge.clock"
                            )
                            .foregroundStyle(.purple)
                            Label("早ければ \(estimatedStartText)", systemImage: "arrow.left")
                            Label("遅くとも \(estimatedLatestText)", systemImage: "arrow.right")
                        }
                        .font(.subheadline.weight(.medium))
                        .accessibilityElement(children: .combine)
                    } else {
                        Toggle("終日", isOn: $draft.isAllDay)
                        DatePicker(
                            "開始",
                            selection: $draft.startDate,
                            displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute]
                        )
                        DatePicker(
                            "終了",
                            selection: endDateBinding,
                            in: endDateRange,
                            displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute]
                        )
                    }
                }

                Section("保存先") {
                    if calendars.isEmpty {
                        Label("書き込み可能なCalendarがありません", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Calendar", selection: $draft.calendarID) {
                            ForEach(calendars) { calendar in
                                HStack {
                                    Circle()
                                        .fill(Color(koyomiHex: calendar.colorHex))
                                        .frame(width: 9, height: 9)
                                    Text("\(calendar.title)（\(calendar.sourceName)）")
                                }
                                .tag(calendar.id)
                            }
                        }
                    }
                }

                CalendarTagEditor(
                    selectedTags: $draft.tags,
                    availableTags: availableTags,
                    excludedTags: CalendarTagEditorPolicy.excludedTags(
                        kind: draft.kind,
                        dateMode: draft.dateMode
                    ),
                    onInputCommitted: {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            scrollProxy.scrollTo("calendar-item-tags-scroll-anchor", anchor: .top)
                        }
                    }
                )
                .id("calendar-item-tags-scroll-anchor")

                Section("詳細") {
                    TextField("場所", text: optionalBinding(\.location))
                        .accessibilityIdentifier("calendar-item-location")
                    TextField("メモ", text: optionalBinding(\.notes), axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("calendar-item-notes")
                }

                Section("通知") {
                    if draft.dateMode == .estimatedWindow {
                        Text("通知は「早ければ」の日の開始を基準にします。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Self.alarmOptions) { option in
                        Toggle(
                            option.title,
                            isOn: Binding(
                                get: { draft.alarmOffsets.contains(option.offset) },
                                set: { enabled in
                                    if enabled {
                                        if !draft.alarmOffsets.contains(option.offset) {
                                            draft.alarmOffsets.append(option.offset)
                                        }
                                    } else {
                                        draft.alarmOffsets.removeAll { $0 == option.offset }
                                    }
                                }
                            )
                        )
                    }
                }

                if draft.dateMode == .exact {
                    Section("繰り返し") {
                        if let recurrence = draft.recurrence,
                           !recurrence.isFullyRepresentable {
                            Label(
                                "Calendarで設定された高度な繰り返しです。元の設定を変更せず保持します。",
                                systemImage: "lock.shield"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            Text(CalendarRecurrenceSummary.text(recurrence))
                        } else {
                            if isDuplicatingUnsupportedRecurrence {
                                Label(
                                    "高度な繰り返しは複製できないため、新しい予定は「なし」から設定します。",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                            Picker("頻度", selection: $recurrenceFrequency) {
                                Text("なし").tag(CalendarRecurrenceFrequency?.none)
                                ForEach(CalendarRecurrenceFrequency.allCases, id: \.self) { frequency in
                                    Text(frequency.title).tag(Optional(frequency))
                                }
                            }
                            if let recurrenceFrequency {
                                Stepper(
                                    "\(recurrenceFrequency.unit)ごと：\(recurrenceInterval)",
                                    value: $recurrenceInterval,
                                    in: 1...99
                                )
                                if recurrenceFrequency == .weekly {
                                    weekdaySelector
                                }
                                Picker("終了", selection: $recurrenceEnd) {
                                    ForEach(RecurrenceEndChoice.allCases) { choice in
                                        Text(choice.title).tag(choice)
                                    }
                                }
                                if recurrenceEnd == .date {
                                    DatePicker(
                                        "終了日",
                                        selection: $recurrenceEndDate,
                                        in: draft.startDate...,
                                        displayedComponents: .date
                                    )
                                } else if recurrenceEnd == .count {
                                    Stepper("回数：\(recurrenceCount)", value: $recurrenceCount, in: 2...999)
                                }
                            }
                        }
                    }
                }

                if context.originalEvent?.isRecurring == true {
                    Section("変更範囲") {
                        Picker("変更範囲", selection: $scope) {
                            Text("この予定のみ").tag(CalendarMutationScope.thisEvent)
                            Text("これ以降すべて").tag(CalendarMutationScope.futureEvents)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KoyomiBackdrop())
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .environment(\.calendar, editorDisplayCalendar)
            .navigationTitle(context.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                        .accessibilityIdentifier("save-calendar-item")
                }
            }
            .onChange(of: draft.isAllDay) { _, isAllDay in
                guard draft.dateMode == .exact, isAllDay else { return }
                let calendar = Calendar.current
                draft.startDate = calendar.startOfDay(for: draft.startDate)
                let minimumEnd = calendar.date(byAdding: .day, value: 1, to: draft.startDate)
                    ?? draft.startDate.addingTimeInterval(86_400)
                draft.endDate = max(calendar.startOfDay(for: draft.endDate), minimumEnd)
            }
            .onChange(of: draft.startDate) { oldValue, newValue in
                guard draft.dateMode == .exact else { return }
                if draft.endDate <= newValue {
                    draft.endDate = newValue.addingTimeInterval(
                        draft.kind == .task ? 1_800 : max(oldValue.distance(to: draft.endDate), 3_600)
                    )
                }
            }
            .onChange(of: estimatedBufferDays) { _, _ in
                applyEstimatedWindow()
            }
            .onChange(of: estimatedCenterDate) { _, _ in
                applyEstimatedWindow()
            }
            .onChange(of: draft.dateMode) { oldMode, newMode in
                guard oldMode != newMode else { return }
                if newMode == .estimatedWindow {
                    activateEstimatedWindow()
                } else {
                    activateExactDate()
                }
            }
            .onChange(of: draft.kind) { _, newKind in
                if newKind == .event, draft.dateMode == .estimatedWindow {
                    draft.dateMode = .exact
                }
                preserveCompletionMeaning(for: newKind)
            }
            .alert(
                "保存できませんでした",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { presented in
                        if !presented { saveError = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "最新状態を確認して、もう一度お試しください。")
            }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(false)
    }

    private var weekdaySelector: some View {
        HStack(spacing: 6) {
            ForEach(CalendarRecurrenceWeekday.allCases, id: \.self) { weekday in
                Button {
                    if !recurrenceWeekdays.insert(weekday).inserted {
                        recurrenceWeekdays.remove(weekday)
                    }
                } label: {
                    Text(weekday.shortTitle)
                        .font(.caption.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .tint(recurrenceWeekdays.contains(weekday) ? .accentColor : .clear)
                .accessibilityLabel("\(weekday.title)を繰り返し")
                .accessibilityValue(
                    CalendarRecurrenceAccessibility.selectionValue(
                        isSelected: recurrenceWeekdays.contains(weekday)
                    )
                )
                .accessibilityAddTraits(
                    recurrenceWeekdays.contains(weekday) ? .isSelected : []
                )
                .accessibilityIdentifier("recurrence-weekday-\(weekday.rawValue)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var estimatedWindow: CalendarEstimatedWindow? {
        CalendarEstimatedWindow.centered(
            on: estimatedCenterDate,
            bufferDays: estimatedBufferDays,
            calendar: .current
        )
    }

    private var estimatedBufferTitle: String {
        CalendarEstimatedWindowText.buffer(days: estimatedBufferDays)
    }

    private var estimatedRangeText: String {
        estimatedWindow.map { CalendarEstimatedWindowText.range($0) } ?? "—"
    }

    private var estimatedWidthText: String {
        estimatedWindow.map { CalendarEstimatedWindowText.width($0) } ?? "—"
    }

    private var estimatedStartText: String {
        estimatedWindow.map { CalendarEstimatedWindowText.date($0.startDate) } ?? "—"
    }

    private var estimatedLatestText: String {
        estimatedWindow.map { CalendarEstimatedWindowText.date($0.latestDate) } ?? "—"
    }

    private func applyEstimatedWindow() {
        guard draft.dateMode == .estimatedWindow, let estimatedWindow else { return }
        draft.startDate = estimatedWindow.startDate
        draft.endDate = estimatedWindow.endDate
        draft.isAllDay = true
        draft.recurrence = nil
        recurrenceFrequency = nil
    }

    private func activateEstimatedWindow() {
        draft.kind = .task
        estimatedCenterDate = Calendar.current.startOfDay(for: draft.startDate)
        draft.isAllDay = true
        draft.recurrence = nil
        recurrenceFrequency = nil
        applyEstimatedWindow()
    }

    private func activateExactDate() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: estimatedCenterDate)
        draft.startDate = start
        draft.endDate = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        draft.isAllDay = true
        draft.recurrence = nil
        recurrenceFrequency = nil
    }

    private func preserveCompletionMeaning(for kind: ManagedCalendarItemKind) {
        let state = CalendarTagEditorPolicy.completionState(
            tags: draft.tags,
            isCompleted: draft.isCompleted,
            kind: kind
        )
        draft.tags = state.tags
        draft.isCompleted = state.isCompleted
    }

    private var endDateBinding: Binding<Date> {
        guard draft.isAllDay else { return $draft.endDate }
        let calendar = Calendar.current
        return Binding(
            get: {
                CalendarAllDayRange.displayEndDate(
                    forExclusiveEnd: draft.endDate,
                    startDate: draft.startDate,
                    calendar: calendar
                )
            },
            set: { displayEnd in
                draft.endDate = CalendarAllDayRange.exclusiveEndDate(
                    forDisplayEnd: displayEnd,
                    startDate: draft.startDate,
                    calendar: calendar
                )
            }
        )
    }

    private var endDateRange: ClosedRange<Date> {
        let minimum = draft.isAllDay
            ? Calendar.current.startOfDay(for: draft.startDate)
            : draft.startDate
        return minimum...Date.distantFuture
    }

    private var editorDisplayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = Calendar.current.timeZone
        return calendar
    }

    private var isDuplicatingUnsupportedRecurrence: Bool {
        guard case let .duplicate(event) = context.purpose else { return false }
        return event.recurrence?.isFullyRepresentable == false
    }

    private var isValid: Bool {
        !draft.readableTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.endDate > draft.startDate
            && calendars.contains(where: { $0.id == draft.calendarID })
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<CalendarItemDraft, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func save() {
        applyEstimatedWindow()
        draft.alarmOffsets.sort()
        draft.recurrence = CalendarRecurrenceEditorPolicy.ruleForSave(
            original: draft.recurrence,
            frequency: recurrenceFrequency,
            interval: recurrenceInterval,
            weekdays: recurrenceWeekdays.sorted { $0.rawValue < $1.rawValue },
            endDate: recurrenceEnd == .date ? recurrenceEndDate : nil,
            occurrenceCount: recurrenceEnd == .count ? recurrenceCount : nil
        )
        if onSave(draft, scope) != nil {
            dismiss()
        } else {
            saveError = "保存できませんでした。最新状態を確認してもう一度お試しください。"
        }
    }


    private static func initialDraft(
        for purpose: CalendarItemEditorPurpose,
        writableCalendars: [CalendarDescriptor],
        selectedDate: Date,
        calendar: Calendar,
        now: Date
    ) -> CalendarItemDraft {
        switch purpose {
        case let .edit(event):
            return CalendarItemDraft(event)
        case let .duplicate(event):
            var draft = CalendarItemDraft(event)
            draft.isCompleted = false
            if draft.recurrence?.isFullyRepresentable == false {
                draft.recurrence = nil
            }
            return draft
        case .createEstimatedTask:
            let selectedDay = calendar.startOfDay(for: selectedDate)
            let center = calendar.date(byAdding: .month, value: 1, to: selectedDay) ?? selectedDay
            let window = CalendarEstimatedWindow.centered(
                on: center,
                bufferDays: 14,
                calendar: calendar
            )
            let fallbackEnd = calendar.date(byAdding: .day, value: 29, to: selectedDay)
                ?? selectedDay.addingTimeInterval(29 * 86_400)
            return CalendarItemDraft(
                kind: .task,
                dateMode: .estimatedWindow,
                readableTitle: "",
                startDate: window?.startDate ?? selectedDay,
                endDate: window?.endDate ?? fallbackEnd,
                isAllDay: true,
                calendarID: writableCalendars.first?.id ?? "",
                isImportant: true
            )
        case let .create(kind):
            let selectedDay = calendar.startOfDay(for: selectedDate)
            let start: Date
            if calendar.isDate(selectedDate, inSameDayAs: now) {
                let minute = calendar.component(.minute, from: now)
                let delta = minute < 30 ? 30 - minute : 60 - minute
                start = calendar.date(byAdding: .minute, value: delta, to: now) ?? now
            } else {
                start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDay) ?? selectedDay
            }
            let duration: TimeInterval = kind == .task ? 1_800 : 3_600
            return CalendarItemDraft(
                kind: kind,
                readableTitle: "",
                startDate: start,
                endDate: start.addingTimeInterval(duration),
                isAllDay: false,
                calendarID: writableCalendars.first?.id ?? ""
            )
        }
    }
}

private struct AlarmOption: Identifiable {
    let offset: TimeInterval
    let title: String
    var id: TimeInterval { offset }
}

private enum RecurrenceEndChoice: String, CaseIterable, Identifiable {
    case never
    case date
    case count

    var id: Self { self }
    var title: String {
        switch self {
        case .never: "なし"
        case .date: "日付"
        case .count: "回数"
        }
    }
}

private extension CalendarRecurrenceFrequency {
    var title: String {
        switch self {
        case .daily: "毎日"
        case .weekly: "毎週"
        case .monthly: "毎月"
        case .yearly: "毎年"
        }
    }

    var unit: String {
        switch self {
        case .daily: "日"
        case .weekly: "週"
        case .monthly: "月"
        case .yearly: "年"
        }
    }
}

private extension CalendarRecurrenceWeekday {
    var shortTitle: String { String(title.prefix(1)) }
    var title: String {
        switch self {
        case .sunday: "日曜"
        case .monday: "月曜"
        case .tuesday: "火曜"
        case .wednesday: "水曜"
        case .thursday: "木曜"
        case .friday: "金曜"
        case .saturday: "土曜"
        }
    }
}
