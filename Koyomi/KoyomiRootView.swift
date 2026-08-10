import SwiftUI

private enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case day = "1日"
    case upcoming = "予定一覧"

    var id: Self { self }
}

struct KoyomiRootView: View {
    @ObservedObject var model: CalendarViewModel
    @State private var displayMode: CalendarDisplayMode = .day
    @State private var isDatePickerPresented = false
    @State private var isCalendarFilterPresented = false

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
            .toolbar {
                if model.authorizationStatus == .fullAccess {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            KoyomiHaptics.perform(.changeCalendarFilter)
                            isCalendarFilterPresented = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "line.3.horizontal.decrease")
                                if model.isCalendarFilterActive {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 6, height: 6)
                                        .offset(x: 3, y: -2)
                                }
                            }
                            .frame(width: 18, height: 18)
                        }
                        .accessibilityLabel("表示するカレンダーを選ぶ")

                        if displayMode == .day {
                            Button {
                                KoyomiHaptics.perform(.selectDate)
                                model.selectToday()
                            } label: {
                                Text("今日")
                            }
                            .accessibilityLabel("今日へ移動")

                            Button {
                                KoyomiHaptics.perform(.selectDate)
                                isDatePickerPresented = true
                            } label: {
                                Image(systemName: "calendar")
                            }
                            .accessibilityLabel("日付を選ぶ")
                        }
                    }
                }
            }
            .sheet(item: $model.selectedEvent) { event in
                EventDetailView(
                    event: event,
                    isPinned: model.isPinned(event),
                    onTogglePin: { model.togglePin(event) }
                )
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
                CalendarFilterSheet(model: model)
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
            VStack(alignment: .leading, spacing: 24) {
                PinnedEventsSection(model: model)
                displayModePicker
                if !model.availableTags.isEmpty {
                    EventTagFilterBar(model: model)
                }

                switch displayMode {
                case .day:
                    DateStrip(model: model)
                    AgendaSection(model: model)
                case .upcoming:
                    UpcomingEventsSection(model: model)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
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

    private var displayModePicker: some View {
        Picker("予定の表示", selection: $displayMode) {
            ForEach(CalendarDisplayMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .onChange(of: displayMode) { _, _ in
            KoyomiHaptics.perform(.switchAgenda)
        }
        .accessibilityIdentifier("calendar-display-mode")
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
