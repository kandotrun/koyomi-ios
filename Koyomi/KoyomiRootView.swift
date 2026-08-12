import SwiftUI

enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case day = "1日"
    case upcoming = "予定一覧"

    var id: Self { self }
}

struct KoyomiRootView: View {
    @ObservedObject var model: CalendarViewModel
    @State private var displayMode: CalendarDisplayMode = .day
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @State private var isDatePickerPresented = false
    @State private var isCalendarFilterPresented = false
    @State private var editorContext: CalendarItemEditorContext?

    var body: some View {
        NavigationStack {
            ZStack {
                KoyomiBackdrop()

                Group {
                    switch model.authorizationStatus {
                    case .fullAccess:
                        calendarContent
                    case .notDetermined:
                        CalendarPermissionView(status: .notDetermined, model: model)
                    case .denied:
                        CalendarPermissionView(status: .denied, model: model)
                    case .restricted:
                        CalendarPermissionView(status: .restricted, model: model)
                    case .writeOnly:
                        CalendarPermissionView(status: .writeOnly, model: model)
                    }
                }
            }
            .navigationTitle("こよみ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.authorizationStatus == .fullAccess {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            isSearchPresented = true
                            Task { @MainActor in isSearchFocused = true }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("予定・タスクを検索")
                        .accessibilityIdentifier("show-calendar-search")

                        Button {
                            KoyomiHaptics.perform(.changeCalendarFilter)
                            isCalendarFilterPresented = true
                        } label: {
                            Image(
                                systemName: isAnyFilterActive
                                    ? "line.3.horizontal.decrease.circle.fill"
                                    : "line.3.horizontal.decrease.circle"
                            )
                        }
                        .accessibilityLabel(
                            isAnyFilterActive
                                ? "表示と絞り込み、条件を適用中"
                                : "表示と絞り込み"
                        )
                        .accessibilityIdentifier("display-options")

                        Menu {
                            Button {
                                editorContext = CalendarItemEditorContext(purpose: .create(.event))
                            } label: {
                                Label("予定を追加", systemImage: "calendar.badge.plus")
                            }
                            Button {
                                editorContext = CalendarItemEditorContext(purpose: .create(.task))
                            } label: {
                                Label("タスクを追加", systemImage: "checkmark.circle.badge.plus")
                            }
                            Button {
                                editorContext = CalendarItemEditorContext(purpose: .createEstimatedTask)
                            } label: {
                                Label("見込みタスクを追加", systemImage: "calendar.badge.clock")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("予定またはタスクを追加")
                        .accessibilityIdentifier("add-calendar-item")
                    }
                }
            }
            .sheet(item: $model.selectedEvent) { event in
                EventDetailView(
                    event: event,
                    calendars: model.calendars,
                    availableTags: model.availableTags,
                    isPinned: model.isPinned,
                    onTogglePin: { event, scope in
                        model.togglePin(event, scope: scope)
                    },
                    onUpdate: { event, draft, scope in
                        model.updateItem(event, with: draft, scope: scope)
                    },
                    onDuplicate: { draft in
                        model.createItem(draft)
                    },
                    onSetTaskCompleted: { event, completed, scope in
                        model.setTaskCompleted(event, completed: completed, scope: scope)
                    },
                    onDelete: { event, scope in
                        model.deleteItem(event, scope: scope)
                    }
                )
            }
            .sheet(item: $editorContext) { context in
                CalendarItemEditorSheet(
                    context: context,
                    calendars: model.calendars,
                    availableTags: model.availableTags,
                    selectedDate: model.selectedDate
                ) { draft, _ in
                    model.createItem(draft)
                }
            }
            .sheet(isPresented: $isDatePickerPresented) {
                DatePickerSheet(
                    selection: Binding(
                        get: { model.selectedDate },
                        set: {
                            KoyomiHaptics.perform(.selectDate)
                            model.selectDate($0)
                        }
                    )
                )
            }
            .sheet(isPresented: $isCalendarFilterPresented) {
                CalendarFilterSheet(model: model, displayMode: $displayMode)
            }
            .overlay(alignment: .top) {
                if let message = model.errorMessage {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .koyomiGlass(tint: .orange, cornerRadius: 18)
                        .padding(.top, 8)
                        .accessibilityLabel(message)
                }
            }
        }
        .task { model.bootstrap() }
    }

    private var calendarContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isSearchPresented || !model.searchText.isEmpty {
                    searchField
                }

                if displayMode == .day {
                    DateStrip(
                        model: model,
                        onOpenCalendar: {
                            KoyomiHaptics.perform(.selectDate)
                            isDatePickerPresented = true
                        }
                    )
                }

                if isAnyFilterActive {
                    activeFilterSummary
                }

                PinnedEventsSection(model: model)

                switch displayMode {
                case .day:
                    AgendaSection(model: model)
                case .upcoming:
                    UpcomingEventsSection(model: model)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("calendar-content-scroll")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 20)
        }
        .refreshable {
            KoyomiHaptics.perform(.refresh)
            model.refresh()
        }
        .overlay {
            if model.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .koyomiGlass(cornerRadius: 24)
                    .accessibilityLabel("読み込み中")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("予定・タスクを検索", text: $model.searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            Button {
                model.searchText = ""
                isSearchFocused = false
                isSearchPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("検索を終了")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 44)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar-search-field")
    }

    private var isAnyFilterActive: Bool {
        model.itemFilter != .all || model.selectedTag != nil || model.isCalendarFilterActive
    }

    private var activeFilterSummary: some View {
        HStack(spacing: 10) {
            Label(activeFilterText, systemImage: "line.3.horizontal.decrease")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                KoyomiHaptics.perform(.changeCalendarFilter)
                model.selectItemFilter(.all)
                model.selectTag(nil)
                model.selectAllCalendars()
            } label: {
                Text("解除")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("すべての絞り込みを解除")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("active-filter-summary")
    }

    private var activeFilterText: String {
        var labels: [String] = []
        if model.itemFilter != .all {
            labels.append(model.itemFilter.title)
        }
        if let tag = model.selectedTag {
            labels.append("#\(tag)")
        }
        if model.isCalendarFilterActive {
            labels.append("カレンダー \(model.selectedCalendarIDs.count)/\(model.calendars.count)")
        }
        return labels.joined(separator: "、")
    }
}

private struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Date

    var body: some View {
        NavigationStack {
            DatePicker("日付", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("日付を選ぶ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") {
                            KoyomiHaptics.perform(.dismiss)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}
