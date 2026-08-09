import SwiftUI

struct KoyomiRootView: View {
    @ObservedObject var model: CalendarViewModel
    @State private var isDatePickerPresented = false

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
                            model.selectToday()
                        } label: {
                            Image(systemName: "scope")
                        }
                        .accessibilityLabel("今日へ移動")

                        Button {
                            isDatePickerPresented = true
                        } label: {
                            Image(systemName: "calendar")
                        }
                        .accessibilityLabel("日付を選ぶ")

                        Button {
                            model.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("予定を更新")
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
                        set: { model.selectDate($0) }
                    )
                )
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
            VStack(alignment: .leading, spacing: 26) {
                PinnedEventsSection(model: model)
                DateStrip(model: model)
                AgendaSection(model: model)
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .refreshable { model.refresh() }
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
                        Button("完了") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}
