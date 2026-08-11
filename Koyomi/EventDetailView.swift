import SwiftUI

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var event: CalendarEvent
    @State private var editorContext: CalendarItemEditorContext?
    @State private var isDeleteConfirmationPresented = false
    @State private var isCompletionScopePresented = false
    @State private var pendingCompletion = false
    @State private var completionUndoAction: CalendarCompletionUndoAction?
    @State private var mutationError: String?

    let calendars: [CalendarDescriptor]
    let isPinned: (CalendarEvent) -> Bool
    let onTogglePin: (CalendarEvent) -> Void
    let onUpdate: (CalendarEvent, CalendarItemDraft, CalendarMutationScope) -> CalendarEvent?
    let onDuplicate: (CalendarItemDraft) -> CalendarEvent?
    let onSetTaskCompleted: (CalendarEvent, Bool, CalendarMutationScope) -> CalendarEvent?
    let onDelete: (CalendarEvent, CalendarMutationScope) -> Bool

    init(
        event: CalendarEvent,
        calendars: [CalendarDescriptor],
        isPinned: @escaping (CalendarEvent) -> Bool,
        onTogglePin: @escaping (CalendarEvent) -> Void,
        onUpdate: @escaping (CalendarEvent, CalendarItemDraft, CalendarMutationScope) -> CalendarEvent?,
        onDuplicate: @escaping (CalendarItemDraft) -> CalendarEvent?,
        onSetTaskCompleted: @escaping (CalendarEvent, Bool, CalendarMutationScope) -> CalendarEvent?,
        onDelete: @escaping (CalendarEvent, CalendarMutationScope) -> Bool
    ) {
        _event = State(initialValue: event)
        self.calendars = calendars
        self.isPinned = isPinned
        self.onTogglePin = onTogglePin
        self.onUpdate = onUpdate
        self.onDuplicate = onDuplicate
        self.onSetTaskCompleted = onSetTaskCompleted
        self.onDelete = onDelete
    }

    private var tint: Color { Color(koyomiHex: event.calendarColorHex) }
    private var metadata: EventTitleMetadata { event.titleMetadata }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCard

                    if event.managementKind == .task {
                        if event.isCompletedTask {
                            Button {
                                requestCompletionChange(false)
                            } label: {
                                Label("未完了に戻す", systemImage: "arrow.uturn.backward.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .tint(.secondary)
                            .disabled(!event.canEdit)
                            .accessibilityIdentifier("task-completion-button")
                        } else {
                            Button {
                                requestCompletionChange(true)
                            } label: {
                                Label("タスクを完了", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(Color(red: 0, green: 0.38, blue: 0.18))
                            .disabled(!event.canEdit)
                            .accessibilityIdentifier("task-completion-button")
                        }
                    }

                    if isPinned(event) {
                        Button {
                            KoyomiHaptics.perform(.togglePin)
                            onTogglePin(event)
                        } label: {
                            Label("ピン留めを解除", systemImage: "pin.slash.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .tint(.primary)
                    } else {
                        Button {
                            KoyomiHaptics.perform(.togglePin)
                            onTogglePin(event)
                        } label: {
                            Label(
                                event.managementKind == .task
                                    ? "このタスクをピン留め"
                                    : "この予定をピン留め",
                                systemImage: "pin.fill"
                            )
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .tint(tint)
                    }

                    if event.canEdit {
                        HStack(spacing: 12) {
                            Button {
                                editorContext = CalendarItemEditorContext(purpose: .edit(event))
                            } label: {
                                Label("編集", systemImage: "pencil")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("edit-calendar-item")

                            Button {
                                editorContext = CalendarItemEditorContext(purpose: .duplicate(event))
                            } label: {
                                Label("複製", systemImage: "plus.square.on.square")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("duplicate-calendar-item")
                        }

                        Button(role: .destructive) {
                            isDeleteConfirmationPresented = true
                        } label: {
                            Label("削除", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .tint(.red)
                        .accessibilityIdentifier("delete-calendar-item")
                    } else {
                        Label(
                            event.calendarID.isEmpty
                                ? "予定の最新情報を読み込めないため、現在は閲覧とピン解除のみ利用できます。"
                                : "このCalendarは読み取り専用です。閲覧とピン留めのみ利用できます。",
                            systemImage: event.calendarID.isEmpty ? "exclamationmark.triangle.fill" : "lock.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .koyomiGlass(cornerRadius: 18)
                    }
                }
                .padding(20)
            }
            .background(KoyomiBackdrop())
            .navigationTitle(event.managementKind == .task ? "タスク" : "予定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        KoyomiHaptics.perform(.dismiss)
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let action = completionUndoAction {
                    HStack(spacing: 12) {
                        Text(action.previousCompletedValue ? "未完了に戻しました" : "タスクを完了しました")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("元に戻す") {
                            undoCompletion(action)
                        }
                        .fontWeight(.bold)
                        .accessibilityIdentifier("undo-management-action")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .koyomiGlass(tint: .accentColor, cornerRadius: 18)
                    .padding(20)
                }
            }
            .sheet(item: $editorContext) { context in
                CalendarItemEditorSheet(
                    context: context,
                    calendars: calendars,
                    selectedDate: event.startDate
                ) { draft, scope in
                    switch context.purpose {
                    case .edit:
                        guard let updated = onUpdate(event, draft, scope) else { return nil }
                        event = updated
                        return updated
                    case .duplicate:
                        return onDuplicate(draft)
                    case .create, .createEstimatedTask:
                        return nil
                    }
                }
            }
            .confirmationDialog(
                "予定を削除しますか？",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                if event.isRecurring {
                    Button("この予定のみ削除", role: .destructive) {
                        delete(scope: .thisEvent)
                    }
                    Button("これ以降を削除", role: .destructive) {
                        delete(scope: .futureEvents)
                    }
                } else {
                    Button("予定を削除", role: .destructive) {
                        delete(scope: .thisEvent)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            }
            .confirmationDialog(
                pendingCompletion ? "タスクを完了する範囲" : "未完了に戻す範囲",
                isPresented: $isCompletionScopePresented,
                titleVisibility: .visible
            ) {
                Button("この予定のみ") {
                    setCompletion(pendingCompletion, scope: .thisEvent)
                }
                Button("これ以降すべて") {
                    setCompletion(pendingCompletion, scope: .futureEvents)
                }
                Button("キャンセル", role: .cancel) {}
            }
            .alert(
                "操作を完了できませんでした",
                isPresented: Binding(
                    get: { mutationError != nil },
                    set: { presented in
                        if !presented { mutationError = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) { mutationError = nil }
            } message: {
                Text(mutationError ?? "最新状態を確認して、もう一度お試しください。")
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(
                    systemName: event.managementKind == .task
                        ? (event.isCompletedTask ? "checkmark.circle.fill" : "circle")
                        : "calendar"
                )
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 52, height: 52)
                    .koyomiGlass(tint: tint, cornerRadius: 18)
                VStack(alignment: .leading, spacing: 5) {
                    if !metadata.containsTag(event.calendarName) {
                        Text(event.calendarName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(metadata.displayTitle)
                        .font(.title2.bold())
                        .strikethrough(event.isCompletedTask)
                        .foregroundStyle(event.isCompletedTask ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !metadata.tags.isEmpty {
                        ScrollView(.horizontal) {
                            EventTagSummary(tags: metadata.tags, limit: metadata.tags.count)
                                .padding(.vertical, 2)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }

            Divider()
            if let estimatedWindow {
                DetailLine(
                    symbol: "calendar.badge.clock",
                    title: "見込み期間",
                    value: "\(estimatedRangeText(estimatedWindow))\n\(CalendarEstimatedWindowText.width(estimatedWindow))",
                    tint: .purple
                )
                DetailLine(
                    symbol: "scope",
                    title: "中心の目安",
                    value: estimatedStatusText(estimatedWindow),
                    tint: .purple
                )
            } else {
                DetailLine(symbol: "clock", title: "日時", value: dateText, tint: tint)
            }
            if let location = event.location, !location.isEmpty {
                DetailLine(symbol: "mappin.and.ellipse", title: "場所", value: location, tint: tint)
            }
            if let notes = event.notes, !notes.isEmpty {
                DetailLine(symbol: "note.text", title: "メモ", value: notes, tint: tint)
            }
            if !event.alarmOffsets.isEmpty {
                DetailLine(
                    symbol: "bell",
                    title: "通知",
                    value: event.alarmOffsets.map(alarmText).joined(separator: "、"),
                    tint: tint
                )
            }
            if let recurrence = event.recurrence {
                DetailLine(symbol: "repeat", title: "繰り返し", value: recurrenceText(recurrence), tint: tint)
            }
        }
        .padding(22)
        .koyomiGlass(tint: tint, cornerRadius: 30)
    }

    private func requestCompletionChange(_ completed: Bool) {
        if event.isRecurring {
            pendingCompletion = completed
            isCompletionScopePresented = true
        } else {
            setCompletion(completed, scope: .thisEvent)
        }
    }

    private func setCompletion(_ completed: Bool, scope: CalendarMutationScope) {
        let previous = event.isCompletedTask
        guard let updated = onSetTaskCompleted(event, completed, scope) else {
            mutationError = "タスクを更新できませんでした。予定が別の端末で変更されていないか確認してください。"
            return
        }
        event = updated
        completionUndoAction = CalendarCompletionUndoAction(
            previousCompletedValue: previous,
            scope: scope
        )
    }

    private func undoCompletion(_ action: CalendarCompletionUndoAction) {
        guard let updated = onSetTaskCompleted(
            event,
            action.previousCompletedValue,
            action.scope
        ) else {
            mutationError = "元の状態へ戻せませんでした。予定の最新状態を確認してください。"
            return
        }
        event = updated
        completionUndoAction = nil
    }

    private func delete(scope: CalendarMutationScope) {
        if onDelete(event, scope) {
            dismiss()
        } else {
            mutationError = "予定を削除できませんでした。予定が別の端末で変更されていないか確認してください。"
        }
    }

    private var estimatedWindow: CalendarEstimatedWindow? {
        CalendarEstimatedWindow(event: event)
    }

    private func estimatedRangeText(_ window: CalendarEstimatedWindow) -> String {
        CalendarEstimatedWindowText.range(window)
    }

    private func estimatedStatusText(_ window: CalendarEstimatedWindow) -> String {
        let center = CalendarEstimatedWindowText.date(window.centerDate)
        if event.isCompletedTask {
            return "\(center)ごろ\n完了済み"
        }
        let status = switch window.status(at: .now) {
        case let .upcoming(daysUntilStart):
            "見込み期間の開始まであと\(daysUntilStart)日"
        case let .withinWindow(daysUntilLatest):
            "見込み期間内・遅い側まであと\(daysUntilLatest)日"
        case let .overdue(days):
            "見込み期間の終了から\(days)日超過・要確認"
        }
        return "\(center)ごろ\n\(status)"
    }

    private var dateText: String {
        CalendarItemDateSummary.text(for: event)
    }

    private func alarmText(_ offset: TimeInterval) -> String {
        switch offset {
        case 0: "開始時刻"
        case -300: "5分前"
        case -900: "15分前"
        case -1_800: "30分前"
        case -3_600: "1時間前"
        case -86_400: "1日前"
        default: "\(Int(abs(offset) / 60))分前"
        }
    }

    private func recurrenceText(_ recurrence: CalendarRecurrenceRule) -> String {
        CalendarRecurrenceSummary.text(recurrence)
    }
}

private struct DetailLine: View {
    let symbol: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
